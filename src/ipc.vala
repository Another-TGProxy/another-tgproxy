// SPDX-License-Identifier: GPL-3.0-or-later
namespace TgWsProxy {

    // A status snapshot pushed by the daemon over the control channel.
    public class Status : Object {
        public bool running = false;
        public string host = "";
        public int port = 0;
        public string secret = "";
        public int64 conn_total = 0;
        public int64 conn_active = 0;
        public int64 bytes_up = 0;
        public int64 bytes_down = 0;
        public string error = "";

        // newline-delimited JSON (one object per line)
        public string to_line () {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("event"); b.add_string_value ("status");
            b.set_member_name ("running"); b.add_boolean_value (running);
            b.set_member_name ("host"); b.add_string_value (host);
            b.set_member_name ("port"); b.add_int_value (port);
            b.set_member_name ("secret"); b.add_string_value (secret);
            b.set_member_name ("error"); b.add_string_value (error);
            b.set_member_name ("stats");
            b.begin_object ();
            b.set_member_name ("total"); b.add_int_value (conn_total);
            b.set_member_name ("active"); b.add_int_value (conn_active);
            b.set_member_name ("up"); b.add_int_value (bytes_up);
            b.set_member_name ("down"); b.add_int_value (bytes_down);
            b.end_object ();
            b.end_object ();
            var gen = new Json.Generator ();
            gen.set_root (b.get_root ());
            return gen.to_data (null) + "\n";
        }

        public static Status? parse (string line) {
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (line, -1);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT)
                    return null;
                var o = root.get_object ();
                var s = new Status ();
                if (o.has_member ("running")) s.running = o.get_boolean_member ("running");
                if (o.has_member ("host")) s.host = o.get_string_member ("host");
                if (o.has_member ("port")) s.port = (int) o.get_int_member ("port");
                if (o.has_member ("secret")) s.secret = o.get_string_member ("secret");
                if (o.has_member ("error")) s.error = o.get_string_member ("error");
                if (o.has_member ("stats")) {
                    var st = o.get_object_member ("stats");
                    if (st.has_member ("total")) s.conn_total = st.get_int_member ("total");
                    if (st.has_member ("active")) s.conn_active = st.get_int_member ("active");
                    if (st.has_member ("up")) s.bytes_up = st.get_int_member ("up");
                    if (st.has_member ("down")) s.bytes_down = st.get_int_member ("down");
                }
                return s;
            } catch (Error e) {
                return null;
            }
        }
    }

    public string command_line (string cmd) {
        var b = new Json.Builder ();
        b.begin_object ();
        b.set_member_name ("cmd"); b.add_string_value (cmd);
        b.end_object ();
        var gen = new Json.Generator ();
        gen.set_root (b.get_root ());
        return gen.to_data (null) + "\n";
    }

    public string? command_of (string line) {
        try {
            var parser = new Json.Parser ();
            parser.load_from_data (line, -1);
            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT)
                return null;
            var o = root.get_object ();
            return o.has_member ("cmd") ? o.get_string_member ("cmd") : null;
        } catch (Error e) {
            return null;
        }
    }

    // First line of a message, clipped to a readable length for inline display.
    // The full text stays available behind a "Details" affordance.
    public static string error_summary (string msg) {
        var first = msg.strip ();
        int nl = first.index_of_char ('\n');
        if (nl >= 0)
            first = first.substring (0, nl).strip ();
        if (first.char_count () > 90)
            first = first.substring (0, first.index_of_nth_char (90)).strip () + "…";
        return first;
    }

    public static string human_bytes (int64 n) {
        double v = (double) n;
        string[] units = { "B", "KB", "MB", "GB", "TB" };
        int u = 0;
        while (v >= 1024 && u < units.length - 1) { v /= 1024; u++; }
        return "%.1f%s".printf (v, units[u]);
    }
}