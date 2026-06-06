// SPDX-License-Identifier: GPL-3.0-or-later
namespace TgWsProxy {

    // Headless background process: a GApplication that runs the proxy engine and
    // a Unix-socket control server for the GUI. Under Flatpak it also publishes a
    // live status to the XDG Background portal (see portal_set_status).
    public class Daemon : GLib.Application {
        Config cfg;
        Engine? engine = null;
        SocketService? control = null;
#if WINDOWS
        string control_token = "";
#endif
        string last_error = "";
        TrayStatus? tray = null;
        Control? control_dbus = null;
        StatusMode current_mode = StatusMode.WINDOW;
        GenericArray<Engine> retired = new GenericArray<Engine> ();
        GenericArray<OutputStream> clients = new GenericArray<OutputStream> ();

        public Daemon () {
            Object (
                application_id: Build.DAEMON_ID,
                flags: ApplicationFlags.IS_SERVICE | ApplicationFlags.ALLOW_REPLACEMENT
            );
        }

        // ---- engine lifecycle ----

        void setup_logging () {
            Logging.setup (cfg);
        }

        bool start_engine () {
            cfg = Config.load ();
            engine = new Engine (cfg.host, (uint16) cfg.port, cfg.secret_bytes ());
            cfg.configure_engine (engine);
            if (!engine.start ()) {
                engine = null;
                last_error = _("Failed to bind %s:%d — port already in use").printf (
                    cfg.host, cfg.port);
                warning ("%s", last_error);
                return false;
            }
            last_error = "";
            message ("proxy started: tg://proxy?server=%s&port=%d&secret=dd%s",
                     cfg.host, cfg.port, cfg.secret);
            return true;
        }

        void stop_engine () {
            if (engine != null) {
                engine.stop ();
                // Keep alive instead of freeing: detached client threads may
                // still reference it; freeing here would be a use-after-free.
                retired.add ((owned) engine);
                engine = null;
            }
        }

        Status snapshot () {
            var s = new Status ();
            s.host = cfg.host;
            s.port = cfg.port;
            s.secret = cfg.secret;
            s.running = engine != null;
            s.error = last_error;
            if (engine != null) {
                s.conn_total = engine.connections_total ();
                s.conn_active = engine.connections_active ();
                s.bytes_up = engine.bytes_up ();
                s.bytes_down = engine.bytes_down ();
            }
            return s;
        }

        // ---- GNOME background status (xdg Background portal) ----

        // SetStatus is sandbox-only — the Background portal returns NotAllowed
        // for non-Flatpak callers, so skip it natively (silent no-op).
        static bool is_sandboxed () {
            return FileUtils.test ("/.flatpak-info", FileTest.EXISTS);
        }

        // Fill the user's status_template with live values.
        string status_message () {
            if (engine == null)
                return _("Proxy stopped");
            var s = cfg.status_template;
            s = s.replace ("{active}", engine.connections_active ().to_string ());
            s = s.replace ("{total}", engine.connections_total ().to_string ());
            s = s.replace ("{up}", human_bytes (engine.bytes_up ()));
            s = s.replace ("{down}", human_bytes (engine.bytes_down ()));
            s = s.replace ("{host}", cfg.host);
            s = s.replace ("{port}", cfg.port.to_string ());
            return s;
        }

        // Create/destroy presenters so that exactly one (the chosen mode's) is
        // alive — selecting any mode tears the others down.
        void reconcile_status_mode () {
            current_mode = Platform.get_default ().mode_of (cfg.status_mode);
#if !DARWIN && !WINDOWS
            // The SNI tray is the daemon's only on Linux; on macOS/Windows the
            // native tray (NSStatusItem / Shell_NotifyIcon) lives in the GUI.
            bool want_tray = current_mode == StatusMode.TRAY;
            if (want_tray && tray == null) setup_tray ();
            else if (!want_tray && tray != null) { tray.close (); tray = null; }
#endif
        }

        // StatusMode.NOTIFICATION is reserved for an Android foreground-service
        // ongoing notification (the canonical mechanism there). Not implemented on
        // desktop: GNOME has no persistent notification, so it would only spam
        // banners. The Android port wires its presenter here.

        void setup_tray () {
            tray = new TrayStatus ();
            tray.open_requested.connect (open_gui);
            tray.open_telegram_requested.connect (open_telegram);
            tray.toggle_requested.connect (toggle_engine);
            tray.restart_requested.connect (restart_engine);
            tray.quit_requested.connect (() => { do_quit (); });
        }

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
            if (engine != null) stop_engine ();
            else start_engine ();
            push_status_all ();
            publish_status ();
        }

        void restart_engine () {
            stop_engine ();
            start_engine ();
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
            if (cfg.secret.length != 32) return;
            var uri = "tg://proxy?server=%s&port=%d&secret=dd%s".printf (
                cfg.host, cfg.port, cfg.secret);
            try {
                AppInfo.launch_default_for_uri (uri, null);
            } catch (Error e) {
                warning ("open telegram failed: %s", e.message);
            }
        }

        // Push the live status to every active presenter.
        void publish_status () {
            if (current_mode == StatusMode.BACKGROUND_PORTAL) portal_set_status ();
            if (tray != null) tray.update (status_message (), engine != null);
            if (control_dbus != null) {
                bool r = engine != null;
                var st = status_message ();
                if (r != control_dbus.running || st != control_dbus.status)
                    control_dbus.publish (r, st);
            }
        }

        void portal_set_status () {
            if (!is_sandboxed ()) return;
            var conn = get_dbus_connection ();
            if (conn == null) return;
            string msg = status_message ();
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

        // ---- control server (Unix socket) ----

        void start_control () throws Error {
            control = new SocketService ();
#if WINDOWS
            // No Unix sockets: listen on an ephemeral loopback TCP port and
            // publish the chosen port + an auth token for the GUI to read.
            var listen = new InetSocketAddress (
                new InetAddress.loopback (SocketFamily.IPV4), 0);
            SocketAddress? effective = null;
            control.add_address (listen, SocketType.STREAM, SocketProtocol.TCP,
                                 null, out effective);
            control_token = gen_control_token ();
            write_control_endpoint (((InetSocketAddress) effective).get_port (),
                                    control_token);
#else
            var sockpath = Paths.control_sock ();
            if (FileUtils.test (sockpath, FileTest.EXISTS))
                FileUtils.unlink (sockpath);   // stale socket from a prior crash
            var addr = new UnixSocketAddress (sockpath);
            control.add_address (addr, SocketType.STREAM, SocketProtocol.DEFAULT, null, null);
            FileUtils.chmod (sockpath, 0600);
#endif
            control.incoming.connect ((conn, src) => {
                handle_control.begin ((SocketConnection) conn);
                return false;
            });
            control.start ();
        }

        void push_status_all () {
            if (clients.length == 0) return;
            var line = snapshot ().to_line ();
            for (int i = clients.length - 1; i >= 0; i--) {
                try {
                    clients[i].write_all (line.data, null);
                } catch (Error e) {
                    clients.remove_index (i);
                }
            }
        }

        async void handle_control (SocketConnection conn) {
            var os = conn.output_stream;
            var dis = new DataInputStream (conn.input_stream);
#if WINDOWS
            // A loopback port is reachable by any local process; require the token
            // (sent as the first line) before trusting the connection.
            try {
                var auth = yield dis.read_line_async (Priority.DEFAULT, null);
                if (auth == null || auth.strip () != control_token) {
                    try { conn.close (); } catch (Error e) { }
                    return;
                }
            } catch (Error e) {
                return;
            }
#endif
            clients.add (os);
            try {
                yield os.write_all_async (snapshot ().to_line ().data,
                                          Priority.DEFAULT, null, null);
                string? line;
                while ((line = yield dis.read_line_async (Priority.DEFAULT, null)) != null) {
                    var cmd = command_of (line);
                    if (cmd == "status") {
                        yield os.write_all_async (snapshot ().to_line ().data,
                                                  Priority.DEFAULT, null, null);
                    } else if (cmd == "reload") {
                        stop_engine ();
                        start_engine ();
                        reconcile_status_mode ();
                        publish_status ();
                        yield os.write_all_async (snapshot ().to_line ().data,
                                                  Priority.DEFAULT, null, null);
                    } else if (cmd == "stop") {
                        do_quit ();
                        break;
                    }
                }
            } catch (Error e) {
                // client gone
            }
            for (int i = 0; i < clients.length; i++)
                if (clients[i] == os) { clients.remove_index (i); break; }
        }

        // ---- GApplication lifecycle ----

        public override void startup () {
            base.startup ();
            hold ();   // keep running with no windows
            Paths.ensure_dir ();
#if WINDOWS
            // No D-Bus / signals on Windows; the GUI stops us by this PID.
            try { FileUtils.set_contents (Paths.pid_file (), Win.pid ().to_string ()); }
            catch (Error e) { warning ("pid write failed: %s", e.message); }
#endif
            cfg = Config.load ();
            setup_logging ();

            start_engine ();
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
            Timeout.add_seconds (2, () => {
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
            stop_engine ();
            if (control != null) control.stop ();
            cleanup_control ();
            base.shutdown ();
        }

        static void cleanup_control () {
#if WINDOWS
            FileUtils.unlink (Paths.control_json ());
            FileUtils.unlink (Paths.pid_file ());
#else
            FileUtils.unlink (Paths.control_sock ());
#endif
        }

        void do_quit () {
            stop_engine ();
            if (tray != null) { tray.close (); tray = null; }
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