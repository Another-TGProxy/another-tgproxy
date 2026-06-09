// SPDX-License-Identifier: GPL-3.0-or-later
namespace TgWsProxy {

    // Headless background process: a GApplication that runs the proxy engine and
    // a Unix-socket control server for the GUI. Under Flatpak it also publishes a
    // live status to the XDG Background portal (see portal_set_status).
    public class Daemon : GLib.Application {
        EngineRunner runner = new EngineRunner ();
        Station.ControlServer? control = null;
        TrayController? tray = null;
#if HAVE_QSHUB
        QshubController? qshub = null;
#endif
        Control? control_dbus = null;
        StatusMode current_mode = StatusMode.WINDOW;
        bool quitting = false;
        uint status_timer = 0;
        string last_portal_msg = "";

        public Daemon () {
            Object (
                application_id: Build.DAEMON_ID,
                flags: ApplicationFlags.IS_SERVICE | ApplicationFlags.ALLOW_REPLACEMENT
            );
        }

        // The engine lifecycle (start/stop/reload/snapshot) lives in the shared
        // EngineRunner; the daemon adds the control server, tray and D-Bus surface.

        // ---- GNOME background status (xdg Background portal) ----

        // SetStatus is sandbox-only — the Background portal returns NotAllowed
        // for non-Flatpak callers, so skip it natively (silent no-op).
        static bool is_sandboxed () {
            return FileUtils.test ("/.flatpak-info", FileTest.EXISTS);
        }

        // Fill the user's status_template with live values.
        string status_message () {
            if (!runner.running)
                return _("Proxy stopped");
            return runner.snapshot ().format (runner.cfg.status_template);
        }

        // Create/destroy presenters so that exactly one (the chosen mode's) is
        // alive — selecting any mode tears the others down.
        void reconcile_status_mode () {
            current_mode = Platform.get_default ().mode_of (runner.cfg.status_mode);
#if !DARWIN && !WINDOWS
            // The SNI tray is the daemon's only on Linux; on macOS/Windows the
            // native tray (NSStatusItem / Shell_NotifyIcon) lives in the GUI.
            bool want_tray = current_mode == StatusMode.TRAY;
            if (want_tray && tray == null) setup_tray ();
            else if (!want_tray && tray != null) { tray.close (); tray = null; }
#endif
#if HAVE_QSHUB
            bool want_qshub = current_mode == StatusMode.QUICK_SETTINGS;
            if (want_qshub && qshub == null) setup_qshub ();
            else if (!want_qshub && qshub != null) { qshub.close (); qshub = null; }
#endif
        }

        // StatusMode.NOTIFICATION is reserved for an Android foreground-service
        // ongoing notification (the canonical mechanism there). Not implemented on
        // desktop: GNOME has no persistent notification, so it would only spam
        // banners. The Android port wires its presenter here.

#if !DARWIN && !WINDOWS
        void setup_tray () {
            tray = new TrayController ();
            tray.open_requested.connect (open_gui);
            tray.open_telegram_requested.connect (open_telegram);
            tray.toggle_requested.connect (toggle_engine);
            tray.restart_requested.connect (restart_engine);
            tray.quit_requested.connect (() => { do_quit (); });
        }
#endif

#if HAVE_QSHUB
        // The GNOME Quick Settings entry via libqshub (the quick-settings-hub
        // extension). Inert when no hub is installed.
        void setup_qshub () {
            qshub = new QshubController ();
            qshub.open_requested.connect (open_gui);
            qshub.open_telegram_requested.connect (open_telegram);
            qshub.toggle_requested.connect (toggle_engine);
            qshub.restart_requested.connect (restart_engine);
            qshub.quit_requested.connect (() => { do_quit (); });
        }
#endif

        // D-Bus control surface for the GNOME Shell quick-settings extension.
        void setup_control () {
            control_dbus = new Control ();
            control_dbus.toggle_requested.connect (toggle_engine);
            control_dbus.restart_requested.connect (restart_engine);
            control_dbus.open_requested.connect (open_gui);
            control_dbus.open_telegram_requested.connect (open_telegram);
            control_dbus.quit_requested.connect (() => { do_quit (); });
            var conn = get_dbus_connection ();
            if (conn == null) return;
            try {
                conn.register_object ("/space/ampernic/AnotherTGProxy/Control",
                                      control_dbus);
            } catch (Error e) {
                warning ("control dbus register failed: %s", e.message);
            }
        }

        void toggle_engine () {
            if (runner.running) runner.stop ();
            else runner.start ();
            push_status_all ();
            publish_status ();
        }

        void restart_engine () {
            runner.reload ();
            push_status_all ();
            publish_status ();
        }

        void open_gui () {
#if DARWIN || WINDOWS
            // No .desktop here; the tray that raises the window lives in the GUI
            // process (NSStatusItem / Shell_NotifyIcon), not in this daemon.
#else
            var info = new DesktopAppInfo (Build.APP_ID_RELEVANT + ".desktop");
            if (info == null) return;
            try {
                info.launch (null, null);
            } catch (Error e) {
                warning ("open gui failed: %s", e.message);
            }
#endif
        }

        void open_telegram () {
            var cfg = runner.cfg;
            if (cfg.secret.length != 32) return;
            var uri = "tg://proxy?server=%s&port=%d&secret=dd%s".printf (
                cfg.host, cfg.port, cfg.secret);
            try {
                Station.open_uri (uri);
            } catch (Error e) {
                warning ("open telegram failed: %s", e.message);
            }
        }

        // Push the live status to every active presenter.
        void publish_status () {
            if (current_mode == StatusMode.BACKGROUND_PORTAL) {
                var msg = status_message ();
                if (msg != last_portal_msg) {   // skip the D-Bus call when unchanged
                    last_portal_msg = msg;
                    portal_set_status (msg);
                }
            }
            if (tray != null) tray.update (status_message (), runner.running);
#if HAVE_QSHUB
            if (qshub != null) qshub.update (status_message (), runner.running);
#endif
            if (control_dbus != null) {
                bool r = runner.running;
                var st = status_message ();
                if (r != control_dbus.running || st != control_dbus.status)
                    control_dbus.publish (r, st);
            }
        }

        void portal_set_status (string msg) {
            if (!is_sandboxed ()) return;
            var conn = get_dbus_connection ();
            if (conn == null) return;
            var b = new VariantBuilder (new VariantType ("a{sv}"));
            b.add ("{sv}", "message", new Variant.string (msg));
            conn.call.begin (
                "org.freedesktop.portal.Desktop",
                "/org/freedesktop/portal/desktop",
                "org.freedesktop.portal.Background",
                "SetStatus",
                new Variant ("(a{sv})", b),
                null, DBusCallFlags.NONE, -1, null);
        }

        // ---- control server (libstation: Unix socket / loopback TCP + token) ----

        void start_control () throws Error {
            control = new Station.ControlServer (Build.DAEMON_ID);
            control.command.connect (on_control_command);
            control.start ();
        }

        void on_control_command (string line) {
            var cmd = command_of (line);
            if (cmd == "status") {
                push_status_all ();
            } else if (cmd == "reload") {
                runner.reload ();
                reconcile_status_mode ();
                publish_status ();
                push_status_all ();
            } else if (cmd == "stop") {
                do_quit ();
            }
        }

        void push_status_all () {
            if (control != null)
                control.broadcast (runner.snapshot ().to_line ().chomp ());
        }

        // ---- GApplication lifecycle ----

        public override void startup () {
            base.startup ();
            hold ();   // keep running with no windows
            Paths.ensure_dir ();
#if WINDOWS
            // No D-Bus / signals on Windows; the GUI stops us by this PID.
            try { FileUtils.set_contents (Paths.pid_file (), Station.get_pid ().to_string ()); }
            catch (Error e) { warning ("pid write failed: %s", e.message); }
#endif
            Logging.setup (runner.cfg);

            runner.start ();
            try {
                start_control ();
            } catch (Error e) {
                warning ("control server failed: %s", e.message);
            }

            var quit_action = new SimpleAction ("quit", null);
            quit_action.activate.connect (() => { do_quit (); });
            add_action (quit_action);

            setup_control ();
            reconcile_status_mode ();
            publish_status ();
            status_timer = Timeout.add_seconds (2, () => {
                push_status_all ();
                publish_status ();
                return Source.CONTINUE;
            });

#if !WINDOWS
            Unix.signal_add (Posix.Signal.TERM, () => { do_quit (); return Source.REMOVE; });
            Unix.signal_add (Posix.Signal.INT, () => { do_quit (); return Source.REMOVE; });
#endif
        }

        public override void activate () {
            // No window: activation just keeps the service alive.
        }

        public override void shutdown () {
            if (status_timer != 0) { Source.remove (status_timer); status_timer = 0; }
            runner.stop ();
            if (control != null) { control.stop (); control = null; }
            cleanup_control ();
            base.shutdown ();
        }

        // libstation owns the control endpoint files; only the Windows pid file
        // (used by the GUI to stop us by PID) is ours to clear.
        static void cleanup_control () {
#if WINDOWS
            FileUtils.unlink (Paths.pid_file ());
#endif
        }

        void do_quit () {
            // Reachable from SIGTERM/SIGINT, the "stop" IPC command, the quit
            // action and the tray — guard so a second trigger doesn't unbalance
            // hold()/release() or quit() twice.
            if (quitting) return;
            quitting = true;
            if (status_timer != 0) { Source.remove (status_timer); status_timer = 0; }
            runner.stop ();
            if (tray != null) { tray.close (); tray = null; }
#if HAVE_QSHUB
            if (qshub != null) { qshub.close (); qshub = null; }
#endif
            if (control != null) { control.stop (); control = null; }
            cleanup_control ();
            release ();   // drop the hold so the app can exit
            quit ();
        }
    }

    public int run_daemon (string[] args) {
        var app = new Daemon ();
        // Don't forward "--daemon" to GApplication's arg handling.
        return app.run ({ args[0] });
    }
}