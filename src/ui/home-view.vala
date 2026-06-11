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
        [GtkChild] private unowned Gtk.Stack buttons;

        public signal void toast (string message);

        private DaemonClient client;
        private ServiceController service;
        private string current_link = "";

        public void bind (DaemonClient client, ServiceController service) {
            this.client = client;
            this.service = service;

            start_btn.clicked.connect (() => service.start ());
            stop_btn.clicked.connect (() => { client.send ("stop"); service.stop (); });
            // Restart the engine in-process via the daemon's control channel: no
            // process churn, no port race, and works without session D-Bus (macOS).
            restart_btn.clicked.connect (() => client.send ("reload"));
            open_btn.clicked.connect (open_in_telegram);
            copy_btn.clicked.connect (() => {
                if (current_link == "") return;
                get_clipboard ().set_text (current_link);
                toast (_("Link copied"));
            });

            client.status_changed.connect (on_status);
            client.connection_changed.connect (on_connection);

            // Until the daemon reports in, assume it is not running.
            stop_btn.sensitive = false;
            restart_btn.sensitive = false;
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
                restart_btn.sensitive = false;
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
            restart_btn.sensitive = r;   // only restart a running proxy
            buttons.visible_child_name = r ? "active" : "inactive";
        }

        private void on_connection (bool connected) {
            buttons.visible_child_name = connected ? "active" : "inactive";
            if (!connected) {
                home_status.icon_name = "network-offline-symbolic";
                home_status.title = _("Stopped");
                home_status.description = _("Daemon is not running");
                start_btn.sensitive = true;
                stop_btn.sensitive = false;
                restart_btn.sensitive = false;
            }
        }
    }
}
