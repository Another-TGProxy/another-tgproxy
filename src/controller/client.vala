// SPDX-License-Identifier: GPL-3.0-or-later
namespace TgWsProxy {

    // GUI-side client of the daemon control channel. Connects to the Unix
    // socket, streams status lines (-> status_changed), sends commands.
    public class DaemonClient : Object {
        public signal void status_changed (Status status);
        public signal void connection_changed (bool connected);

#if ANDROID
        // Single-process on Android: the "control channel" is the in-process
        // EngineHost rather than a Unix socket to a separate daemon.
        public void start () {
            var h = EngineHost.instance ();
            h.status_changed.connect ((s) => status_changed (s));
            connection_changed (true);
            status_changed (h.snapshot ());
        }
        public void stop () { }
        public void send (string cmd) {
            var h = EngineHost.instance ();
            if (cmd == "stop") h.stop ();
            else if (cmd == "reload") h.reload ();
            else if (cmd == "status") status_changed (h.snapshot ());
        }
#else
        // Transport (Unix socket / loopback TCP + token) and auto-reconnect come
        // from libstation; the status/command protocol on top stays ours.
        Station.ControlClient? ctl = null;

        public void start () {
            if (ctl != null) return;
            ctl = new Station.ControlClient (Build.DAEMON_ID);
            ctl.connected.connect ((c) => {
                connection_changed (c);
                // Pull a snapshot immediately rather than waiting for the next push.
                if (c) ctl.send (command_line ("status").chomp ());
            });
            ctl.message.connect ((line) => {
                var s = Status.parse (line);
                if (s != null) status_changed (s);
            });
            ctl.start ();
        }

        public void stop () {
            if (ctl != null) { ctl.stop (); ctl = null; }
        }

        public void send (string cmd) {
            if (ctl != null) ctl.send (command_line (cmd).chomp ());
        }
#endif
    }
}