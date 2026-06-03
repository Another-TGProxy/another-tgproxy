// SPDX-License-Identifier: GPL-3.0-or-later
namespace TgWsProxy {

    // GUI-side client of the daemon control channel. Connects to the Unix
    // socket, streams status lines (-> status_changed), sends commands.
    public class DaemonClient : Object {
        public signal void status_changed (Status status);
        public signal void connection_changed (bool connected);

        SocketConnection? conn = null;
        OutputStream? os = null;
        bool want_connected = false;
        bool connected = false;

        public void start () {
            want_connected = true;
            try_connect.begin ();
        }

        public void stop () {
            want_connected = false;
            close_conn ();
        }

        void close_conn () {
            if (conn != null) {
                try { conn.close (); } catch (Error e) { }
            }
            conn = null;
            os = null;
            if (connected) {
                connected = false;
                connection_changed (false);
            }
        }

        async void try_connect () {
            while (want_connected && !connected) {
                var path = Paths.control_sock ();
                if (FileUtils.test (path, FileTest.EXISTS)) {
                    try {
                        var client = new SocketClient ();
                        conn = yield client.connect_async (
                            new UnixSocketAddress (path), null);
                        os = conn.output_stream;
                        connected = true;
                        connection_changed (true);
                        read_loop.begin ();
                        return;
                    } catch (Error e) {
                        conn = null;
                    }
                }
                // retry shortly
                yield sleep_async (1000);
            }
        }

        async void read_loop () {
            try {
                var dis = new DataInputStream (conn.input_stream);
                string? line;
                while ((line = yield dis.read_line_async (Priority.DEFAULT, null)) != null) {
                    var s = Status.parse (line);
                    if (s != null) status_changed (s);
                }
            } catch (Error e) {
                // fallthrough to reconnect
            }
            close_conn ();
            if (want_connected) try_connect.begin ();
        }

        public void send (string cmd) {
            if (os == null) return;
            try {
                os.write_all (command_line (cmd).data, null);
            } catch (Error e) { }
        }

        static async void sleep_async (uint ms) {
            Timeout.add (ms, () => { sleep_async.callback (); return Source.REMOVE; });
            yield;
        }
    }
}