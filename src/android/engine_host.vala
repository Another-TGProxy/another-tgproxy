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
        GenericArray<Engine> retired = new GenericArray<Engine> ();

        construct {
            cfg = Config.load ();
            // No daemon on Android to capture the engine's GLib log output; the
            // shared logger routes it to proxy.log (with the same rotation).
            Logging.setup (cfg);
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

        string last_notif = "";

        void push () {
            var s = snapshot ();
            status_changed (s);

            // The foreground-service notification is the Android status display;
            // keep it in step with the live stats (only re-post on change).
            var text = engine != null
                ? s.format (cfg.status_template.length > 0 ? cfg.status_template
                            : "Telegram · {active} conn. · ↑{up} ↓{down}")
                : _("Proxy stopped");
            if (text != last_notif) {
                last_notif = text;
                Station.android_foreground_set_text (text);
            }
        }
    }
}
#endif
