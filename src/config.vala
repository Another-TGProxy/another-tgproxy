// SPDX-License-Identifier: GPL-3.0-or-later
namespace TgWsProxy {

    // App paths (Linux: $XDG_CONFIG_HOME/AnotherTGProxy).
    namespace Paths {
        public string app_dir () {
            return Path.build_filename (Environment.get_user_config_dir (),
                                        Build.APP_DIRNAME);
        }
        public string config_file () {
            return Path.build_filename (app_dir (), "config.json");
        }
        public string control_sock () {
            return Path.build_filename (app_dir (), "control.sock");
        }
        // Windows has no Unix sockets: the daemon listens on a loopback TCP port
        // and writes the chosen port + an auth token here for the GUI to read.
        public string control_json () {
            return Path.build_filename (app_dir (), "control.json");
        }
        public string pid_file () {
            return Path.build_filename (app_dir (), "daemon.pid");
        }
        public string log_file () {
            return Path.build_filename (app_dir (), "proxy.log");
        }
        public void ensure_dir () {
            DirUtils.create_with_parents (app_dir (), 0700);
        }
    }

    // The persisted settings (config.json), shared by daemon + GUI.
    public class Config : Object {
        public string host = "127.0.0.1";
        public int port = 1443;
        public string secret = "";                       // 32 hex chars
        public string[] dc_ip = { "2:149.154.167.220", "4:149.154.167.220" };
        public bool cfproxy = true;
        public bool verify_cf = true;                    // verify CF domain TLS cert
        public string[] cfproxy_user_domain = {};
        public string[] cfproxy_worker_domain = {};
        public string fake_tls_domain = "";
        public bool verbose = false;
        public bool log_to_file = true;
        public int buf_kb = 256;
        public int pool_size = 4;
        public double log_max_mb = 5;
        public bool check_updates = true;
        public string appearance = "auto";               // auto|light|dark
        public bool tray = false;                         // Linux default off
        public bool autostart = false;
        // Background-status text (GNOME "Background Apps", Flatpak only).
        // Placeholders: {active} {total} {up} {down} {host} {port} {secret}
        public string status_template = "Telegram · {active} conn. · ↑{up} ↓{down}";
        public string status_mode = "auto";              // auto|window|tray|background|quicksettings|notification

        public static string gen_secret () {
            var sb = new StringBuilder ();
            for (int i = 0; i < 16; i++)
                sb.append_printf ("%02x", (uint8) Random.int_range (0, 256));
            return sb.str;
        }

        // 16 raw bytes of the hex secret (for the engine).
        public uint8[] secret_bytes () {
            var r = new uint8[16];
            for (int i = 0; i < 16 && 2 * i + 1 < secret.length; i++)
                r[i] = (uint8) ((secret[2 * i].xdigit_value () << 4)
                                | secret[2 * i + 1].xdigit_value ());
            return r;
        }

        public static Config load () {
            var c = new Config ();
            var path = Paths.config_file ();
            if (!FileUtils.test (path, FileTest.EXISTS)) {
                c.secret = gen_secret ();
                c.save ();
                return c;
            }
            try {
                var parser = new Json.Parser ();
                parser.load_from_file (path);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT)
                    return c;
                var o = root.get_object ();
                if (o.has_member ("host")) c.host = o.get_string_member ("host");
                if (o.has_member ("port")) c.port = (int) o.get_int_member ("port");
                if (o.has_member ("secret")) c.secret = o.get_string_member ("secret");
                if (o.has_member ("dc_ip")) c.dc_ip = str_array (o, "dc_ip");
                if (o.has_member ("cfproxy")) c.cfproxy = o.get_boolean_member ("cfproxy");
                if (o.has_member ("verify_cf")) c.verify_cf = o.get_boolean_member ("verify_cf");
                if (o.has_member ("cfproxy_user_domain"))
                    c.cfproxy_user_domain = str_array (o, "cfproxy_user_domain");
                if (o.has_member ("cfproxy_worker_domain"))
                    c.cfproxy_worker_domain = str_array (o, "cfproxy_worker_domain");
                if (o.has_member ("fake_tls_domain"))
                    c.fake_tls_domain = o.get_string_member ("fake_tls_domain");
                if (o.has_member ("verbose")) c.verbose = o.get_boolean_member ("verbose");
                if (o.has_member ("log_to_file")) c.log_to_file = o.get_boolean_member ("log_to_file");
                if (o.has_member ("buf_kb")) c.buf_kb = (int) o.get_int_member ("buf_kb");
                if (o.has_member ("pool_size")) c.pool_size = (int) o.get_int_member ("pool_size");
                if (o.has_member ("log_max_mb")) c.log_max_mb = o.get_double_member ("log_max_mb");
                if (o.has_member ("check_updates")) c.check_updates = o.get_boolean_member ("check_updates");
                if (o.has_member ("appearance")) c.appearance = o.get_string_member ("appearance");
                if (o.has_member ("tray")) c.tray = o.get_boolean_member ("tray");
                if (o.has_member ("autostart")) c.autostart = o.get_boolean_member ("autostart");
                if (o.has_member ("status_template"))
                    c.status_template = o.get_string_member ("status_template");
                if (o.has_member ("status_mode"))
                    c.status_mode = o.get_string_member ("status_mode");
            } catch (Error e) {
                warning ("config load failed: %s", e.message);
            }
            if (c.secret.length != 32) {
                c.secret = gen_secret ();
                c.save ();
            }
            return c;
        }

        static string[] str_array (Json.Object o, string key) {
            var arr = o.get_array_member (key);
            var r = new string[arr.get_length ()];
            for (uint i = 0; i < arr.get_length (); i++)
                r[i] = arr.get_string_element (i);
            return r;
        }

        static void add_str_array (Json.Builder b, string key, string[] vals) {
            b.set_member_name (key);
            b.begin_array ();
            foreach (var v in vals) b.add_string_value (v);
            b.end_array ();
        }

        public void save () {
            Paths.ensure_dir ();
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("host"); b.add_string_value (host);
            b.set_member_name ("port"); b.add_int_value (port);
            b.set_member_name ("secret"); b.add_string_value (secret);
            add_str_array (b, "dc_ip", dc_ip);
            b.set_member_name ("cfproxy"); b.add_boolean_value (cfproxy);
            b.set_member_name ("verify_cf"); b.add_boolean_value (verify_cf);
            add_str_array (b, "cfproxy_user_domain", cfproxy_user_domain);
            add_str_array (b, "cfproxy_worker_domain", cfproxy_worker_domain);
            b.set_member_name ("fake_tls_domain"); b.add_string_value (fake_tls_domain);
            b.set_member_name ("verbose"); b.add_boolean_value (verbose);
            b.set_member_name ("log_to_file"); b.add_boolean_value (log_to_file);
            b.set_member_name ("buf_kb"); b.add_int_value (buf_kb);
            b.set_member_name ("pool_size"); b.add_int_value (pool_size);
            b.set_member_name ("log_max_mb"); b.add_double_value (log_max_mb);
            b.set_member_name ("check_updates"); b.add_boolean_value (check_updates);
            b.set_member_name ("appearance"); b.add_string_value (appearance);
            b.set_member_name ("tray"); b.add_boolean_value (tray);
            b.set_member_name ("autostart"); b.add_boolean_value (autostart);
            b.set_member_name ("status_template"); b.add_string_value (status_template);
            b.set_member_name ("status_mode"); b.add_string_value (status_mode);
            b.end_object ();

            var gen = new Json.Generator ();
            gen.set_root (b.get_root ());
            gen.pretty = true;
            try {
                gen.to_file (Paths.config_file ());
            } catch (Error e) {
                warning ("config save failed: %s", e.message);
            }
        }

        // Apply dc_ip + fallback settings to a freshly-constructed engine.
        public void configure_engine (Engine e) {
            foreach (var entry in dc_ip) {
                var parts = entry.split (":", 2);
                if (parts.length == 2) {
                    int dc = int.parse (parts[0]);
                    e.add_dc (dc, parts[1]);
                }
            }
            e.set_cfproxy (cfproxy);
            e.set_verify_cf (verify_cf);
            foreach (var d in cfproxy_user_domain)
                if (d.strip () != "") e.add_cf_domain (d.strip ());
            foreach (var d in cfproxy_worker_domain)
                if (d.strip () != "") e.add_worker_domain (d.strip ());
            e.set_fake_tls (fake_tls_domain.strip ());
            e.set_pool_size (pool_size);
        }
    }
}