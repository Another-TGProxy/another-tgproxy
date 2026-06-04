// SPDX-License-Identifier: GPL-3.0-or-later
#if ANDROID
namespace TgWsProxy {

    // Android is single-process: there is no separate daemon, no D-Bus and no
    // Unix-socket IPC. The proxy Engine runs inside the GUI process and this
    // singleton drives it, emitting the same Status snapshots the desktop daemon
    // would push over the control channel. DaemonClient/ServiceController route
    // their calls here instead of to a socket.
    public class EngineHost : Object {
        static EngineHost? _instance = null;
        public static EngineHost instance () {
            if (_instance == null) _instance = new EngineHost ();
            return _instance;
        }

        public signal void status_changed (Status status);
        public signal void failed (string message);

        Config cfg;
        Engine? engine = null;
        string last_error = "";
        uint poll_id = 0;
        FileStream? logfp = null;
        GenericArray<Engine> retired = new GenericArray<Engine> ();

        construct {
            cfg = Config.load ();
            setup_logging ();
        }

        // No daemon to capture the engine's GLib log output on Android, so route
        // it to the same proxy.log the LogView tails (mirrors Daemon.setup_logging).
        void setup_logging () {
            if (!cfg.log_to_file) return;
            Paths.ensure_dir ();
            logfp = FileStream.open (Paths.log_file (), "a");
            Log.set_default_handler ((domain, level, msg) => {
                var ts = new DateTime.now_local ().format ("%H:%M:%S");
                var line = "%s  %s\n".printf (ts, msg);
                if (logfp != null) { logfp.puts (line); logfp.flush (); }
            });
        }

        public bool running { get { return engine != null; } }

        public void start () {
            if (engine != null) return;
            cfg = Config.load ();
            engine = new Engine (cfg.host, (uint16) cfg.port, cfg.secret_bytes ());
            cfg.configure_engine (engine);
            if (!engine.start ()) {
                engine = null;
                last_error = _("Failed to bind %s:%d — port already in use").printf (
                    cfg.host, cfg.port);
                failed (last_error);
                push ();
                return;
            }
            last_error = "";
            if (poll_id == 0)
                poll_id = Timeout.add_seconds (1, () => { push (); return Source.CONTINUE; });
            push ();
        }

        public void stop () {
            if (engine != null) {
                engine.stop ();
                // Detached client threads may still hold it; keep it alive.
                retired.add ((owned) engine);
                engine = null;
            }
            if (poll_id != 0) { Source.remove (poll_id); poll_id = 0; }
            push ();
        }

        public void reload () { stop (); start (); }

        public Status snapshot () {
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

        void push () { status_changed (snapshot ()); }
    }
}
#endif
