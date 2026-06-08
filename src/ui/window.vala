// SPDX-License-Identifier: GPL-3.0-or-later
namespace TgWsProxy {

    [GtkTemplate (ui = "/space/ampernic/AnotherTGProxy/ui/window.ui")]
    public class Window : Adw.ApplicationWindow {

        [GtkChild] private unowned Adw.ToastOverlay toast_overlay;
        [GtkChild] private unowned Adw.Banner conn_banner;
        [GtkChild] private unowned Adw.Banner err_banner;
        [GtkChild] private unowned Adw.Banner update_banner;
        [GtkChild] private unowned HomeView home_view;
        [GtkChild] private unowned SettingsView settings_view;
        [GtkChild] private unowned LogView log_view;

        private Config cfg;
        private DaemonClient client;
        private ServiceController service;
        private string error_detail = "";

        public Window (Gtk.Application app) {
            Object (application: app);
        }

        construct {
            this.title = Build.APP_NAME;
            cfg = Config.load ();
            service = new ServiceController (cfg);
            client = new DaemonClient ();

            var act_about = new SimpleAction ("about", null);
            act_about.activate.connect (show_about);
            add_action (act_about);
            var act_quit = new SimpleAction ("quit", null);
            act_quit.activate.connect (() => application.quit ());
            add_action (act_quit);

            home_view.bind (client, service);
            settings_view.bind (cfg, client, service);
            log_view.start ();
            home_view.toast.connect ((m) => { toast (m); });
            settings_view.toast.connect ((m) => { toast (m); });

            conn_banner.button_clicked.connect (() => service.start ());
            err_banner.button_clicked.connect (open_error_details);
            client.connection_changed.connect (on_connection);
            client.status_changed.connect (on_status);
            service.failed.connect (present_error);
            client.start ();

            // Route this (GUI) process's GLib output to proxy.log so the update
            // check below is visible in the in-app log. No-op on Android, where the
            // in-process EngineHost already set the logger up.
            Logging.attach (cfg);

            // Notify about a newer GitHub release where no repo manages updates
            // (Windows/macOS/Android/AppImage). Native/Flatpak Linux uses its repo.
            if (cfg.check_updates && Platform.get_default ().updates_relevant ()) {
                updater = new Station.Updates ("Another-TGProxy/another-tgproxy", Build.VERSION);
                updater.available.connect (on_update_available);
                update_banner.button_clicked.connect (open_update);
                updater.check (Build.VERSION.contains ("-"));
            }
        }

        private Station.Updates? updater = null;
        private string update_url = "";

        private void on_update_available (string version, string url, string notes) {
            update_url = url;
            update_banner.title = _("Update available: %s").printf (version);
            update_banner.revealed = true;
        }

        private void open_update () {
            if (update_url == "")
                return;
#if ANDROID
            var s = get_surface ();
            if (s != null) Station.android_open_uri (s, update_url);
#else
            try { Station.open_uri (update_url); }
            catch (Error e) { warning ("open release page: %s", e.message); }
#endif
        }

        // On macOS/Windows the app lives on in the tray after the window is
        // destroyed; stop this window's control client so its reconnect loop and
        // socket don't linger until finalization.
        public override void dispose () {
            if (client != null) client.stop ();
            base.dispose ();
        }

        private void toast (string msg) {
            toast_overlay.add_toast (new Adw.Toast (msg) { timeout = 2 });
        }

        private void on_connection (bool connected) {
            conn_banner.revealed = !connected;
        }

        private void on_status (Status s) {
            if (s.error != "")
                present_error (s.error);
            else
                err_banner.revealed = false;
        }

        // Show errors briefly in the banner; the full text (which can be long or
        // multi-line, e.g. from the engine) stays a click away in a dialog.
        private void present_error (string msg) {
            error_detail = msg.strip ();
            err_banner.title = error_summary (msg);
            err_banner.button_label = (error_detail != err_banner.title) ? _("Details") : "";
            err_banner.revealed = true;
        }

        private void open_error_details () {
            if (error_detail == "")
                return;
            var label = new Gtk.Label (error_detail) {
                wrap = true,
                wrap_mode = Pango.WrapMode.WORD_CHAR,
                selectable = true,
                xalign = 0,
                yalign = 0
            };
            label.add_css_class ("monospace");
            var scroller = new Gtk.ScrolledWindow () {
                child = label,
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                propagate_natural_height = true,
                max_content_height = 360,
                width_request = 320
            };
            var dialog = new Adw.AlertDialog (_("Error details"), null) {
                extra_child = scroller
            };
            dialog.add_response ("close", _("Close"));
            dialog.present (this);
        }

        private void show_about () {
            var about = new Adw.AboutDialog () {
                application_name = Build.APP_NAME,
                application_icon = Build.APP_ID_RELEVANT,
                developer_name = "Ampernic",
                version = Build.VERSION,
                license_type = Gtk.License.GPL_3_0,
                website = Build.HOMEPAGE,
                issue_url = Build.BUGTRACKER
            };
            about.present (this);
        }
    }
}
