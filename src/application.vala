// SPDX-License-Identifier: GPL-3.0-or-later
namespace TgWsProxy {

    public class Application : Adw.Application {

        public Application () {
            Object (
                application_id: Build.APP_ID,
                flags: ApplicationFlags.DEFAULT_FLAGS
            );
        }

        protected override void startup () {
            base.startup ();
            // Resolve our app icon (incl. the .Devel variant) by name even when
            // running uninstalled: the icons are bundled in the app resources.
            Gtk.IconTheme.get_for_display (Gdk.Display.get_default ())
                .add_resource_path ("/" + Build.APP_ID.replace (".", "/") + "/icons");
        }

        protected override void activate () {
            var win = this.active_window;
            if (win == null) {
                win = new Window (this);
            }
            win.present ();
        }
    }
}