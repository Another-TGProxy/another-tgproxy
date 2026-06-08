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
        static bool verbose = false;
        static int64 since_trim = 0;   // bytes written since the last cap check

        public static void setup (Config cfg) {
            if (!cfg.log_to_file) return;
            Paths.ensure_dir ();
            size_cap_mb = cfg.log_max_mb;
            verbose = cfg.verbose;

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
            // Drop DEBUG/INFO unless verbose — a replaced default handler bypasses
            // GLib's own G_MESSAGES_DEBUG gating, so without this every debug line
            // would hit the file.
            if (!verbose && (level & (LogLevelFlags.LEVEL_DEBUG | LogLevelFlags.LEVEL_INFO)) != 0)
                return;
            var line = "%s  %s\n".printf (
                new DateTime.now_local ().format ("%H:%M:%S"), msg);
            stderr.printf ("%s", line);
            mtx.lock ();
            if (logfp != null) {
                logfp.puts (line);
                logfp.flush ();
                // Responsive cap: trim as soon as we've written ~cap bytes, so a
                // burst can't blow far past the limit between the 120s ticks.
                since_trim += line.length;
                if (since_trim >= (int64) (size_cap_mb * 1024 * 1024))
                    trim_locked ();
            }
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
            mtx.lock ();
            trim_locked ();
            mtx.unlock ();
        }

        // Cap the file to ~size_cap_mb by keeping only its tail. Reads at most
        // `cap` bytes (not the whole file), so memory stays bounded no matter how
        // large the file grew. Caller must hold mtx.
        static void trim_locked () {
            since_trim = 0;
            int64 cap = (int64) (size_cap_mb * 1024 * 1024);
            if (cap <= 0) return;
            var path = Paths.log_file ();
            Posix.Stat st;
            if (Posix.stat (path, out st) != 0 || (int64) st.st_size <= cap) return;

            var rf = FileStream.open (path, "r");
            if (rf == null) return;
            rf.seek ((long) ((int64) st.st_size - cap), FileSeek.SET);
            var buf = new uint8[(int) cap];
            size_t n = rf.read (buf);
            rf = null;
            if (n == 0) return;

            // Start at the first line boundary so we don't keep a partial line.
            size_t begin = 0;
            for (size_t i = 0; i < n; i++)
                if (buf[i] == '\n') { begin = i + 1; break; }

            logfp = null;   // close the append handle before truncating
            var wf = FileStream.open (path, "w");
            if (wf != null && n > begin)
                wf.write (buf[begin : n]);
            wf = null;
            logfp = FileStream.open (path, "a");
        }
    }
}
