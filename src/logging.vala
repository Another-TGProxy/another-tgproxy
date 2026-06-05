// SPDX-License-Identifier: GPL-3.0-or-later
namespace TgWsProxy {

    // Shared file logging for the engine, used by both the desktop daemon and the
    // Android in-process host. Routes GLib log output to proxy.log and keeps that
    // file bounded: on startup it rotates so only the last two run sessions are
    // retained, and a periodic check caps the live file at cfg.log_max_mb. The
    // engine logs from its worker threads, so writes are mutex-guarded.
    public class Logging {
        const string SESSION_MARK = "=== session";

        static Mutex mtx;
        static FileStream? logfp = null;
        static uint trim_id = 0;
        static double size_cap_mb = 5;

        public static void setup (Config cfg) {
            if (!cfg.log_to_file) return;
            Paths.ensure_dir ();
            size_cap_mb = cfg.log_max_mb;

            // Keep only the most recent existing session; appending this run's
            // marker below then leaves the file holding the last two sessions.
            keep_last_session ();

            mtx.lock ();
            logfp = FileStream.open (Paths.log_file (), "a");
            if (logfp != null) {
                logfp.printf ("%s %s ===\n", SESSION_MARK,
                              new DateTime.now_local ().format ("%Y-%m-%d %H:%M:%S"));
                logfp.flush ();
            }
            mtx.unlock ();

            Log.set_default_handler (handler);

            // Bound a long-running single session too.
            if (trim_id == 0)
                trim_id = Timeout.add_seconds (120, () => { enforce_size (); return Source.CONTINUE; });
        }

        static void handler (string? domain, LogLevelFlags level, string msg) {
            var line = "%s  %s\n".printf (
                new DateTime.now_local ().format ("%H:%M:%S"), msg);
            stderr.printf ("%s", line);
            mtx.lock ();
            if (logfp != null) { logfp.puts (line); logfp.flush (); }
            mtx.unlock ();
        }

        static void keep_last_session () {
            var path = Paths.log_file ();
            if (!FileUtils.test (path, FileTest.EXISTS)) return;
            string contents;
            try { FileUtils.get_contents (path, out contents); }
            catch (Error e) { return; }
            int idx = contents.last_index_of (SESSION_MARK);
            if (idx > 0) {
                try { FileUtils.set_contents (path, contents.substring (idx)); }
                catch (Error e) { }
            }
        }

        static void enforce_size () {
            int64 cap = (int64) (size_cap_mb * 1024 * 1024);
            if (cap <= 0) return;
            var path = Paths.log_file ();
            Posix.Stat st;
            if (Posix.stat (path, out st) != 0 || st.st_size <= cap) return;

            mtx.lock ();
            string contents;
            bool ok = false;
            try { FileUtils.get_contents (path, out contents); ok = true; }
            catch (Error e) { }
            if (ok) {
                int start = (int) (contents.length - cap);
                if (start < 0) start = 0;
                int nl = contents.index_of_char ('\n', start);
                string kept = (nl >= 0) ? contents.substring (nl + 1) : contents.substring (start);
                logfp = null;   // close before rewriting
                try { FileUtils.set_contents (path, kept); } catch (Error e) { }
                logfp = FileStream.open (path, "a");
            }
            mtx.unlock ();
        }
    }
}
