// SPDX-License-Identifier: GPL-3.0-or-later
namespace TgWsProxy {

    [GtkTemplate (ui = "/space/ampernic/AnotherTGProxy/ui/log-view.ui")]
    public class LogView : Adw.Bin {

        [GtkChild] private unowned Gtk.ScrolledWindow scrolled;
        [GtkChild] private unowned Gtk.TextView log_view;

        // Cap the in-view buffer so a long session doesn't grow it without bound;
        // when exceeded we drop whole lines off the top.
        const int MAX_CHARS = 200000;
        const int TRIM_TO = 150000;

        private bool follow = true;
        private int64 read_pos = 0;
        private uint tail_id = 0;

        construct {
            var vadj = scrolled.vadjustment;
            // Pin to the bottom as the content height grows, but only while
            // "following" — which turns off as soon as the user scrolls up and
            // back on when they return to the bottom.
            vadj.changed.connect (() => {
                if (follow) vadj.value = vadj.upper - vadj.page_size;
            });
            vadj.value_changed.connect (() => {
                follow = vadj.value >= vadj.upper - vadj.page_size - 1.0;
            });

            // Tail only while the view is mapped (its ViewStack page is shown):
            // this stops the 1s poll when another tab is up and — crucially —
            // when the window is destroyed, so the timer can't outlive the widget
            // and fire into a disposed TextView.
            map.connect (() => {
                refresh ();
                if (tail_id == 0)
                    tail_id = Timeout.add_seconds (1, () => { refresh (); return Source.CONTINUE; });
            });
            unmap.connect (() => {
                if (tail_id != 0) { Source.remove (tail_id); tail_id = 0; }
            });
        }

        public void start () {
            refresh ();
        }

        // Append only what was added since the last read (so scrolling stays put
        // and smooth); reload from scratch if the file shrank (session rotation).
        private void refresh () {
            var path = Paths.log_file ();
            Posix.Stat st;
            if (Posix.stat (path, out st) != 0) {
                if (read_pos != 0) { log_view.buffer.text = ""; read_pos = 0; }
                return;
            }
            if (st.st_size < read_pos) {
                log_view.buffer.text = "";
                read_pos = 0;
            }
            if (st.st_size == read_pos) return;

            var f = FileStream.open (path, "r");
            if (f == null) return;
            if (read_pos > 0) f.seek ((long) read_pos, FileSeek.SET);

            var sb = new StringBuilder ();
            uint8 buf[8192];
            size_t n;
            while ((n = f.read (buf)) > 0)
                sb.append_len ((string) buf, (ssize_t) n);
            read_pos = st.st_size;

            if (sb.len > 0) append (sb.str);
        }

        private void append (string text) {
            var buf = log_view.buffer;
            Gtk.TextIter end;
            buf.get_end_iter (out end);
            buf.insert (ref end, text, -1);

            if (buf.get_char_count () > MAX_CHARS) {
                Gtk.TextIter start, cut;
                buf.get_start_iter (out start);
                buf.get_iter_at_offset (out cut, buf.get_char_count () - TRIM_TO);
                cut.forward_line ();   // cut on a line boundary
                buf.delete (ref start, ref cut);
            }
            // The vadjustment "changed" handler pins to the bottom once the new
            // text has been laid out (when following).
        }
    }
}
