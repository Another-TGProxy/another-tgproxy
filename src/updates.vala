// SPDX-License-Identifier: GPL-3.0-or-later
namespace TgWsProxy {

    // Update notifier for the platforms WITHOUT a managing repository — Windows,
    // macOS and Android (and Linux AppImage). It queries the project's GitHub
    // releases and, if a newer version than this build exists, emits
    // update_available so the UI can show a banner + a download link. Installing is
    // left to the user (the binaries are unsigned; an auto-installer would need its
    // own signature verification). Native/Flatpak Linux updates via its repo, so it
    // is skipped there. HTTP goes through GIO (a TLS SocketClient) so it has no
    // extra dependency and works on every platform incl. Android.
    public class UpdateChecker : Object {
        public signal void update_available (string version, string url, string notes);

        const string API_HOST = "api.github.com";
        const string API_PATH = "/repos/Another-TGProxy/another-tgproxy/releases?per_page=15";

        // Whether in-app update notification is meaningful for this delivery.
        public static bool relevant () {
            var pf = Platform.get_default ();
            switch (pf.os) {
                case OsKind.WINDOWS:
                case OsKind.MACOS:
                    return true;
                default:
                    break;
            }
#if ANDROID
            return true;   // sideloaded APK: no store managing it
#else
            // Linux: only AppImage lacks a repo; native/Flatpak update via theirs.
            return pf.os == OsKind.LINUX && pf.delivery == DeliveryKind.APPIMAGE;
#endif
        }

        // include_prerelease: consider -beta/-rc releases too (use when this build
        // is itself a prerelease, so a beta user is offered the next beta).
        public void check (bool include_prerelease) {
            fetch.begin (include_prerelease);
        }

        async void fetch (bool include_prerelease) {
            try {
                var client = new SocketClient ();
                client.tls = true;
                client.timeout = 15;
                var conn = yield client.connect_to_host_async (API_HOST, 443, null);

                // HTTP/1.0 so the response is delimited by EOF (no chunked
                // transfer-encoding to decode); the body is then just read to end.
                var req = @"GET $API_PATH HTTP/1.0\r\n"
                    + @"Host: $API_HOST\r\n"
                    + "User-Agent: another-tgproxy\r\n"
                    + "Accept: application/vnd.github+json\r\n"
                    + "Connection: close\r\n\r\n";
                yield conn.output_stream.write_all_async (req.data, Priority.DEFAULT, null, null);

                var dis = new DataInputStream (conn.input_stream);
                var status = yield dis.read_line_async (Priority.DEFAULT, null);
                if (status == null || !(" 200" in status))
                    return;
                // Skip headers up to the blank line.
                string? line;
                while ((line = yield dis.read_line_async (Priority.DEFAULT, null)) != null
                       && line.strip () != "")
                    ;
                // Body to EOF (Connection: close).
                var body = new ByteArray ();
                uint8 buf[8192];
                ssize_t n;
                while ((n = yield dis.read_async (buf, Priority.DEFAULT, null)) > 0)
                    body.append (buf[0:n]);
                handle ((string) body.data, (ssize_t) body.len, include_prerelease);
            } catch (Error e) {
                debug ("update check failed: %s", e.message);
            }
        }

        void handle (string body, ssize_t len, bool include_prerelease) {
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (body, len);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.ARRAY)
                    return;
                var arr = root.get_array ();
                // Releases are newest-first; the first usable one decides.
                for (uint i = 0; i < arr.get_length (); i++) {
                    var o = arr.get_object_element (i);
                    if (o.get_boolean_member_with_default ("draft", false))
                        continue;
                    if (!include_prerelease
                        && o.get_boolean_member_with_default ("prerelease", false))
                        continue;
                    var tag = o.has_member ("tag_name") ? o.get_string_member ("tag_name") : "";
                    if (tag == "")
                        continue;
                    if (cmp_version (strip_v (tag), strip_v (Build.VERSION)) > 0) {
                        var url = o.has_member ("html_url") ? o.get_string_member ("html_url") : "";
                        var notes = o.has_member ("body") ? o.get_string_member ("body") : "";
                        update_available (strip_v (tag), url, notes);
                    }
                    return;
                }
            } catch (Error e) {
                debug ("update parse failed: %s", e.message);
            }
        }

        static string strip_v (string s) {
            return (s.length > 0 && (s[0] == 'v' || s[0] == 'V')) ? s.substring (1) : s;
        }

        // Compare "MAJOR.MINOR.PATCH[-prerelease]": >0 if a is newer, 0 equal,
        // <0 older. A release outranks a prerelease of the same core; two
        // prereleases compare lexically.
        static int cmp_version (string a, string b) {
            string a_core, a_pre, b_core, b_pre;
            split_version (a, out a_core, out a_pre);
            split_version (b, out b_core, out b_pre);

            var an = a_core.split (".");
            var bn = b_core.split (".");
            int n = int.max (an.length, bn.length);
            for (int i = 0; i < n; i++) {
                int av = (i < an.length) ? int.parse (an[i]) : 0;
                int bv = (i < bn.length) ? int.parse (bn[i]) : 0;
                if (av != bv)
                    return (av > bv) ? 1 : -1;
            }
            if (a_pre == "" && b_pre != "") return 1;
            if (a_pre != "" && b_pre == "") return -1;
            return strcmp (a_pre, b_pre);
        }

        static void split_version (string v, out string core, out string pre) {
            int dash = v.index_of_char ('-');
            if (dash >= 0) {
                core = v.substring (0, dash);
                pre = v.substring (dash + 1);
            } else {
                core = v;
                pre = "";
            }
        }
    }
}
