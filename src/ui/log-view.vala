// SPDX-License-Identifier: GPL-3.0-or-later
namespace TgWsProxy {

    [GtkTemplate (ui = "/space/ampernic/AnotherTGProxy/ui/log-view.ui")]
    public class LogView : Adw.Bin {

        [GtkChild] private unowned Gtk.ScrolledWindow scrolled;
        [GtkChild] private unowned Gtk.TextView log_view;

        private bool follow = true;

        construct {
            var vadj = scrolled.vadjustment;
            // The text view lays out lazily, so the height (upper) updates
            // asynchronously. Pin to the bottom whenever it changes — but only
            // while "following", which turns off when the user scrolls up.
            vadj.changed.connect (() => {
                if (follow) vadj.value = vadj.upper - vadj.page_size;
            });
            vadj.value_changed.connect (() => {
                follow = vadj.value >= vadj.upper - vadj.page_size - 1.0;
            });
        }

        public void start () {
            refresh ();
            Timeout.add_seconds (1, () => { refresh (); return Source.CONTINUE; });
        }

        private void refresh () {
            var path = Paths.log_file ();
            if (!FileUtils.test (path, FileTest.EXISTS)) return;
            string contents;
            try {
                FileUtils.get_contents (path, out contents);
            } catch (Error e) {
                return;
            }
            if (contents.length > 65536)
                contents = contents.substring (contents.length - 65536);
            var buf = log_view.buffer;
            if (buf.text == contents) return;
            buf.text = contents;
            // The vadjustment "changed" handler pins to the bottom once the new
            // text has been laid out (if we're following the tail).
        }
    }
}
