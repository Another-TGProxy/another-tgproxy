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

        // Engine lifecycle is the shared EngineRunner; this host adds the 1s status
        // poll + the foreground-service notification (the Android status display).
        EngineRunner runner = new EngineRunner ();
        uint poll_id = 0;

        construct {
            // No daemon on Android to capture the engine's GLib log output; the
            // shared logger routes it to proxy.log (with the same rotation).
            Logging.setup (runner.cfg);
        }

        public bool running { get { return runner.running; } }

        public void start () {
            if (runner.running) return;
            if (!runner.start ()) {
                failed (runner.error);
                push ();
                return;
            }
            if (poll_id == 0)
                poll_id = Timeout.add_seconds (1, () => { push (); return Source.CONTINUE; });
            push ();
        }

        public void stop () {
            runner.stop ();
            if (poll_id != 0) { Source.remove (poll_id); poll_id = 0; }
            push ();
        }

        public void reload () { stop (); start (); }

        public Status snapshot () { return runner.snapshot (); }

        string last_notif = "";

        void push () {
            var s = snapshot ();
            status_changed (s);

            // The foreground-service notification is the Android status display;
            // keep it in step with the live stats (only re-post on change).
            var tmpl = runner.cfg.status_template;
            var text = runner.running
                ? s.format (tmpl.length > 0 ? tmpl : "Telegram · {active} conn. · ↑{up} ↓{down}")
                : _("Proxy stopped");
            if (text != last_notif) {
                last_notif = text;
                Station.android_foreground_set_text (text);
            }
        }
    }
}
#endif
