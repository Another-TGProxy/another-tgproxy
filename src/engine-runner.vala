// SPDX-License-Identifier: GPL-3.0-or-later
namespace TgWsProxy {

    // Owns the proxy Engine's lifecycle, independent of how it's hosted: the
    // desktop daemon (a separate process with a control server) and the Android
    // in-process host (a foreground-service notification) both drive this. Loads
    // the config, starts/stops/reloads the engine, and produces a live Status
    // snapshot. Stopped engines are kept alive rather than freed — detached client
    // threads may still reference one, so freeing on reload would be a use-after-free.
    public class EngineRunner : Object {
        public Config cfg { get; private set; }
        Engine? engine = null;
        string last_error = "";
        GenericArray<Engine> retired = new GenericArray<Engine> ();

        public bool running { get { return engine != null; } }
        public string error { get { return last_error; } }

        public EngineRunner () {
            cfg = Config.load ();
        }

        // Start the engine (re-reading the config first). Returns whether it is now
        // running; on failure the reason is in error.
        public bool start () {
            if (engine != null) return true;
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
            // Don't log the secret — proxy.log is shown in the LogView and may be
            // attached to bug reports; the secret is effectively a password.
            message ("proxy started on %s:%d", cfg.host, cfg.port);
            return true;
        }

        public void stop () {
            if (engine != null) {
                engine.stop ();
                sweep_retired ();
                retired.add ((owned) engine);
                engine = null;
            }
        }

        public bool reload () {
            stop ();
            return start ();
        }

        // A stopped engine is parked in `retired` because its detached bridge
        // threads may still touch it; they drain within ~1s of stop() (the listen
        // fd is closed and the per-conn poll times out), after which active==0 and
        // it's safe to drop. Reclaim drained ones so the list can't grow without
        // bound over a long-lived daemon that's reloaded repeatedly.
        void sweep_retired () {
            for (int i = (int) retired.length - 1; i >= 0; i--) {
                if (retired[i].connections_active () == 0)
                    retired.remove_index (i);
            }
        }

        public Status snapshot () {
            sweep_retired ();
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
    }
}
