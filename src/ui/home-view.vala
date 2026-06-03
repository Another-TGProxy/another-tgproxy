// SPDX-License-Identifier: GPL-3.0-or-later
namespace TgWsProxy {

    [GtkTemplate (ui = "/space/ampernic/AnotherTGProxy/ui/home-view.ui")]
    public class HomeView : Adw.Bin {

        [GtkChild] private unowned Adw.StatusPage home_status;
        [GtkChild] private unowned Adw.ActionRow link_row;
        [GtkChild] private unowned Gtk.Button start_btn;
        [GtkChild] private unowned Gtk.Button stop_btn;
        [GtkChild] private unowned Gtk.Button restart_btn;
        [GtkChild] private unowned Gtk.Button open_btn;
        [GtkChild] private unowned Gtk.Button copy_btn;

        public signal void toast (string message);

        private DaemonClient client;
        private ServiceController service;
        private string current_link = "";

        public void bind (DaemonClient client, ServiceController service) {
            this.client = client;
            this.service = service;

            start_btn.clicked.connect (() => service.start ());
            stop_btn.clicked.connect (() => { client.send ("stop"); service.stop (); });
            restart_btn.clicked.connect (() => service.restart ());
            open_btn.clicked.connect (open_in_telegram);
            copy_btn.clicked.connect (() => {
                if (current_link == "") return;
                get_clipboard ().set_text (current_link);
                toast (_("Link copied"));
            });

            client.status_changed.connect (on_status);
            client.connection_changed.connect (on_connection);
        }

        private void open_in_telegram () {
            if (current_link == "") return;
            var launcher = new Gtk.UriLauncher (current_link);
            launcher.launch.begin (get_root () as Gtk.Window, null, (obj, res) => {
                try {
                    launcher.launch.end (res);
                } catch (Error e) {
                    toast (_("Failed to open Telegram: %s").printf (e.message));
                }
            });
        }

        private void on_status (Status s) {
            if (s.error != "") {
                home_status.icon_name = "dialog-error-symbolic";
                home_status.title = _("Error");
                home_status.description = error_summary (s.error);
                start_btn.sensitive = true;
                stop_btn.sensitive = true;
                return;
            }
            bool r = s.running;
            home_status.icon_name = r ? "network-transmit-receive-symbolic"
                                      : "network-offline-symbolic";
            home_status.title = r ? _("Running") : _("Stopped");
            home_status.description =
                _("Connections: %lld active / %lld total\n↑ %s    ↓ %s").printf (
                    s.conn_active, s.conn_total,
                    human_bytes (s.bytes_up), human_bytes (s.bytes_down));
            if (s.secret.length == 32) {
                current_link = "tg://proxy?server=%s&port=%d&secret=dd%s".printf (
                    s.host, s.port, s.secret);
                link_row.subtitle = current_link;
            }
            start_btn.sensitive = !r;
            stop_btn.sensitive = r;
        }

        private void on_connection (bool connected) {
            if (!connected) {
                home_status.icon_name = "network-offline-symbolic";
                home_status.title = _("Stopped");
                home_status.description = _("Daemon is not running");
                start_btn.sensitive = true;
                stop_btn.sensitive = false;
            }
        }
    }
}
