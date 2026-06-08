// SPDX-License-Identifier: GPL-3.0-or-later
namespace TgWsProxy {

    // Manages the background daemon: spawns it as a detached subprocess of the
    // same binary (works for a native install and inside the Flatpak sandbox,
    // with no separate .desktop to install); autostart via an XDG autostart entry.
    public class ServiceController : Object {
        public signal void failed (string message);

        private Config cfg;

        public ServiceController (Config cfg) {
            this.cfg = cfg;
#if ANDROID
            EngineHost.instance ().failed.connect ((m) => failed (m));
#endif
        }

#if ANDROID
        // Single-process on Android: drive the in-process EngineHost directly.
        public void start () { EngineHost.instance ().start (); }
        public void stop () { EngineHost.instance ().stop (); }
        public void restart () { EngineHost.instance ().reload (); }
        public bool is_active () { return EngineHost.instance ().running; }
        public void set_autostart (bool on) { }
        public bool is_autostart () { return false; }
#else
#if !WINDOWS
        static string object_path () {
            return "/" + Build.DAEMON_ID.replace (".", "/");
        }
#endif

        // Start the daemon. Prefer D-Bus activation so it gets its own scope and
        // survives this GUI closing (essential under Flatpak, where a child of the
        // GUI would die with the GUI's sandbox instance); fall back to spawning the
        // binary directly when no activatable service is installed (dev builds).
        public void start () {
            if (is_active ()) return;
            // The proxy port may be held by a daemon we can't see from here — e.g.
            // another instance running in a different environment (a Flatpak daemon
            // whose control socket is hidden inside its sandbox). The loopback port
            // is shared, so probing it catches that case; report instead of spawning
            // a second daemon that would just fail to bind in silence.
            if (proxy_port_in_use ()) {
                failed (_("Port %d is already in use — the proxy may already be running, possibly in another environment (e.g. Flatpak).").printf (cfg.port));
                return;
            }
#if WINDOWS
            // No D-Bus activation on Windows; the same .exe re-runs in --daemon
            // mode as an independent process (it outlives this GUI on its own).
            try {
                new Subprocess (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE,
                                daemon_exec (), "--daemon");
                verify_started.begin ();
            } catch (Error e) {
                failed (_("Failed to start the service: %s").printf (e.message));
            }
#else
            // Running as an AppImage we have no D-Bus service of our own; the one
            // installed on the system may belong to a different delivery (e.g. a
            // Flatpak), and activating it would launch THAT daemon instead. So spawn
            // our own binary directly ($APPIMAGE re-runs the image in --daemon mode).
            bool is_appimage = Environment.get_variable ("APPIMAGE") != null;
            if (!is_appimage && dbus_activate ()) {
                verify_started.begin ();
                return;
            }
            try {
                new Subprocess (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE,
                                daemon_exec (), "--daemon");
                verify_started.begin ();
            } catch (Error e) {
                failed (_("Failed to start the service: %s").printf (e.message));
            }
#endif
        }

        // True if something is already listening on the configured proxy address.
        bool proxy_port_in_use () {
            var ip = new InetAddress.from_string (cfg.host);
            if (ip == null) return false; // not a literal IP: skip the probe
            try {
                var addr = new InetSocketAddress.from_string (cfg.host, (uint) cfg.port);
                var sock = new Socket (ip.get_family (), SocketType.STREAM, SocketProtocol.TCP);
                bool busy = false;
                try {
                    // On POSIX, bind with SO_REUSEADDR like the daemon does, so a
                    // just-closed port lingering in TIME_WAIT doesn't look "in use"
                    // (a live daemon still yields EADDRINUSE). On Windows
                    // SO_REUSEADDR instead lets two sockets share a port, so the
                    // probe must bind WITHOUT it to detect the running daemon.
#if WINDOWS
                    sock.bind (addr, false);
#else
                    sock.bind (addr, true);
#endif
                } catch (Error e) {
                    busy = true;
                }
                try { sock.close (); } catch (Error e) { }
                return busy;
            } catch (Error e) {
                return false;
            }
        }

        // After a start attempt, give the daemon a moment to come up; if it never
        // claims its bus name and the port stays free, the launch failed.
        async void verify_started () {
            for (int i = 0; i < 12 && !is_active (); i++)
                yield sleep_async (250);
            if (!is_active () && !proxy_port_in_use ())
                failed (_("The service failed to start."));
        }

        static async void sleep_async (uint ms) {
            Timeout.add (ms, () => { sleep_async.callback (); return Source.REMOVE; });
            yield;
        }

#if !WINDOWS
        bool dbus_activate () {
            try {
                var conn = Bus.get_sync (BusType.SESSION);
                conn.call_sync (
                    "org.freedesktop.DBus", "/org/freedesktop/DBus",
                    "org.freedesktop.DBus", "StartServiceByName",
                    new Variant ("(su)", Build.DAEMON_ID, 0),
                    new VariantType ("(u)"), DBusCallFlags.NONE, -1, null);
                return true;
            } catch (Error e) {
                return false;
            }
        }
#endif

#if WINDOWS
        // No D-Bus on Windows: the daemon writes its PID; stop it by that PID
        // (the GUI shares the .exe image name, so taskkill /IM would hit both).
        public void stop () {
            string pid;
            try {
                if (!FileUtils.get_contents (Paths.pid_file (), out pid)) return;
            } catch (Error e) {
                return;
            }
            pid = pid.strip ();
            if (pid == "") return;
            try {
                new Subprocess (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE,
                                "taskkill", "/PID", pid, "/T", "/F");
            } catch (Error e) {
                warning ("taskkill failed: %s", e.message);
            }
        }

        public void restart () { stop (); start (); }

        // Active if something is listening on the proxy port (the daemon binds it).
        public bool is_active () {
            return proxy_port_in_use ();
        }

        // Autostart at login = an HKCU\...\Run value launching the daemon.
        const string RUN_KEY = "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run";

        public void set_autostart (bool on) {
            try {
                if (on) {
                    // Launch the GUI minimized so the tray appears on login and
                    // brings the proxy up; --minimized keeps the window hidden.
                    var cmd = "\"%s\" --minimized".printf (daemon_exec ());
                    new Subprocess (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE,
                                    "reg", "add", RUN_KEY, "/v", Build.APP_DIRNAME,
                                    "/t", "REG_SZ", "/d", cmd, "/f");
                } else {
                    new Subprocess (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE,
                                    "reg", "delete", RUN_KEY, "/v", Build.APP_DIRNAME, "/f");
                }
            } catch (Error e) {
                warning ("autostart reg failed: %s", e.message);
            }
        }

        public bool is_autostart () {
            try {
                var p = new Subprocess (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE,
                                        "reg", "query", RUN_KEY, "/v", Build.APP_DIRNAME);
                p.wait (null);
                return p.get_if_exited () && p.get_exit_status () == 0;
            } catch (Error e) {
                return false;
            }
        }

        static string daemon_exec () {
            return Station.get_executable_path () ?? "another-tgproxy.exe";
        }
#else
        // Ask the daemon to quit via its exported GAction (org.freedesktop.Application).
        public void stop () {
            try {
                var conn = Bus.get_sync (BusType.SESSION);
                // Build the (sava{sv}) tuple from ready-made children: a format
                // string like "(sava{sv})" makes g_variant_new expect builders for
                // the av / a{sv}, and passing values there aborts the process.
                var args = new Variant.tuple ({
                    new Variant.string ("quit"),
                    new Variant.array (VariantType.VARIANT, {}),
                    new Variant.array (new VariantType ("{sv}"), {})
                });
                conn.call_sync (
                    Build.DAEMON_ID,
                    object_path (),
                    "org.freedesktop.Application",
                    "ActivateAction",
                    args,
                    null, DBusCallFlags.NONE, -1, null);
            } catch (Error e) {
                // fall back to nothing; the GUI also sends IPC "stop"
            }
        }

        public void restart () { stop (); start (); }

        // Running if the daemon owns its bus name.
        public bool is_active () {
            try {
                var conn = Bus.get_sync (BusType.SESSION);
                var r = conn.call_sync (
                    "org.freedesktop.DBus", "/org/freedesktop/DBus",
                    "org.freedesktop.DBus", "NameHasOwner",
                    new Variant ("(s)", Build.DAEMON_ID),
                    new VariantType ("(b)"), DBusCallFlags.NONE, -1, null);
                bool owned;
                r.get ("(b)", out owned);
                return owned;
            } catch (Error e) {
                return false;
            }
        }

        // Autostart at login. The mechanism is per-platform: a LaunchAgent on
        // macOS, the xdg-desktop Background portal under Flatpak (the sandbox
        // can't write the host's autostart dir), an XDG autostart .desktop on a
        // native Linux install.
        public void set_autostart (bool on) {
#if DARWIN
            set_autostart_launchagent (on);
#else
            if (Platform.get_default ().delivery == DeliveryKind.FLATPAK)
                request_background_autostart (on);
            else
                set_autostart_xdg (on);
#endif
        }

        public bool is_autostart () {
#if DARWIN
            return FileUtils.test (launchagent_file (), FileTest.EXISTS);
#else
            // The portal offers no query; reflect the stored preference.
            if (Platform.get_default ().delivery == DeliveryKind.FLATPAK)
                return Config.load ().autostart;
            return FileUtils.test (autostart_file (), FileTest.EXISTS);
#endif
        }

#if DARWIN
        static string launchagent_file () {
            return Path.build_filename (Environment.get_home_dir (),
                "Library", "LaunchAgents", Build.DAEMON_ID + ".plist");
        }

        // Run the bundle launcher (it sets the GTK runtime env, then exec's the
        // real binary) as a per-user agent; RunAtLoad starts the proxy at login.
        void set_autostart_launchagent (bool on) {
            var path = launchagent_file ();
            if (on) {
                DirUtils.create_with_parents (Path.get_dirname (path), 0755);
                var launcher = Path.build_filename (
                    Path.get_dirname (daemon_exec ()), "launcher");
                var plist =
                    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
                    "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n" +
                    "<plist version=\"1.0\"><dict>\n" +
                    "  <key>Label</key><string>%s</string>\n".printf (Build.DAEMON_ID) +
                    "  <key>ProgramArguments</key><array><string>%s</string><string>--daemon</string></array>\n".printf (launcher) +
                    "  <key>RunAtLoad</key><true/>\n" +
                    "</dict></plist>\n";
                try { FileUtils.set_contents (path, plist); }
                catch (Error e) { warning ("launchagent write failed: %s", e.message); }
                launchctl ("load", path);
            } else {
                launchctl ("unload", path);
                FileUtils.unlink (path);
            }
        }

        static void launchctl (string verb, string plist) {
            try {
                new Subprocess (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE,
                                "launchctl", verb, "-w", plist);
            } catch (Error e) { /* best effort; RunAtLoad applies next login */ }
        }
#else
        void set_autostart_xdg (bool on) {
            var path = autostart_file ();
            if (on) {
                DirUtils.create_with_parents (
                    Path.build_filename (Environment.get_user_config_dir (), "autostart"), 0755);
                var exe = daemon_exec ();
                // An AppImage has no installed D-Bus service to activate, so the
                // autostart entry must just exec it (DBusActivatable would make the
                // session try — and fail — to activate the bus name).
                bool is_appimage = Environment.get_variable ("APPIMAGE") != null;
                var contents =
                    "[Desktop Entry]\n" +
                    "Type=Application\n" +
                    "Name=%s\n".printf (Build.APP_NAME) +
                    "Exec=\"%s\" --daemon\n".printf (exe) +
                    "Icon=%s\n".printf (Build.APP_ID_RELEVANT) +
                    "Terminal=false\n" +
                    "DBusActivatable=%s\n".printf (is_appimage ? "false" : "true") +
                    "NoDisplay=true\n" +
                    "X-GNOME-Autostart-Delay=10\n";
                try { FileUtils.set_contents (path, contents); }
                catch (Error e) { warning ("autostart write failed: %s", e.message); }
            } else {
                FileUtils.unlink (path);
            }
        }

        static string autostart_file () {
            return Path.build_filename (Environment.get_user_config_dir (),
                                        "autostart", Build.DAEMON_ID + ".desktop");
        }

        // Flatpak: the host autostart dir is outside the sandbox; ask the
        // xdg-desktop Background portal to register/clear an autostart entry that
        // launches the app in --daemon mode.
        void request_background_autostart (bool on) {
            try {
                var conn = Bus.get_sync (BusType.SESSION);
                var opts = new VariantBuilder (new VariantType ("a{sv}"));
                opts.add ("{sv}", "reason", new Variant.string (
                    _("Run the proxy in the background at login")));
                opts.add ("{sv}", "autostart", new Variant.boolean (on));
                opts.add ("{sv}", "background", new Variant.boolean (on));
                opts.add ("{sv}", "commandline",
                    new Variant.strv ({ Build.GETTEXT_PACKAGE, "--daemon" }));
                opts.add ("{sv}", "dbus-activatable", new Variant.boolean (false));
                conn.call.begin (
                    "org.freedesktop.portal.Desktop",
                    "/org/freedesktop/portal/desktop",
                    "org.freedesktop.portal.Background",
                    "RequestBackground",
                    new Variant ("(sa{sv})", "", opts),
                    new VariantType ("(o)"), DBusCallFlags.NONE, -1, null);
            } catch (Error e) {
                warning ("background portal autostart failed: %s", e.message);
            }
        }
#endif

        static string daemon_exec () {
            // The macOS .app launcher exports the real binary path (there is no
            // /proc/self/exe and the binary is not on PATH).
            var mac = Environment.get_variable ("ANOTHER_TGPROXY_EXE");
            if (mac != null && mac != "")
                return mac;
            // In an AppImage, $APPIMAGE is the outer image (re-runnable); /proc/self/exe
            // may point at the bundled loader inside the mount, which is not.
            var appimage = Environment.get_variable ("APPIMAGE");
            if (appimage != null && appimage != "")
                return appimage;
            return Station.get_executable_path () ?? "another-tgproxy";
        }
#endif
#endif
    }
}