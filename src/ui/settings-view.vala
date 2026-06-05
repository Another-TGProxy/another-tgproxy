// SPDX-License-Identifier: GPL-3.0-or-later
namespace TgWsProxy {

    [GtkTemplate (ui = "/space/ampernic/AnotherTGProxy/ui/settings-view.ui")]
    public class SettingsView : Adw.Bin {

        [GtkChild] private unowned Adw.Banner verify_cf_banner;
        [GtkChild] private unowned Adw.EntryRow host_row;
        [GtkChild] private unowned Adw.SpinRow port_row;
        [GtkChild] private unowned Adw.PasswordEntryRow secret_row;
        [GtkChild] private unowned Gtk.Button regen_btn;
        [GtkChild] private unowned Adw.EntryRow dc_row;
        [GtkChild] private unowned Adw.SwitchRow cfproxy_row;
        [GtkChild] private unowned Adw.SwitchRow verify_cf_row;
        [GtkChild] private unowned Adw.SpinRow pool_row;
        [GtkChild] private unowned Adw.SwitchRow logfile_row;
        [GtkChild] private unowned Adw.SwitchRow autostart_row;
        [GtkChild] private unowned Adw.PreferencesGroup status_display_group;
        [GtkChild] private unowned Adw.ToggleGroup status_mode_group;
        [GtkChild] private unowned Adw.PreferencesGroup status_text_group;
        [GtkChild] private unowned Adw.EntryRow status_row;
        [GtkChild] private unowned Adw.ButtonRow notif_settings_row;
        [GtkChild] private unowned Adw.ButtonRow save_row;

        public signal void toast (string message);

        private Config cfg;
        private DaemonClient client;
        private ServiceController service;

        public void bind (Config cfg, DaemonClient client, ServiceController service) {
            this.cfg = cfg;
            this.client = client;
            this.service = service;

            host_row.text = cfg.host;
            port_row.value = cfg.port;
            secret_row.text = cfg.secret;
            dc_row.text = string.joinv (" ", cfg.dc_ip);
            cfproxy_row.active = cfg.cfproxy;
            verify_cf_row.active = cfg.verify_cf;
            verify_cf_banner.revealed = !cfg.verify_cf;
            pool_row.value = cfg.pool_size;
            logfile_row.active = cfg.log_to_file;
            autostart_row.active = service.is_autostart ();
            status_row.text = cfg.status_template;

            regen_btn.clicked.connect (() => { secret_row.text = Config.gen_secret (); });
            verify_cf_row.notify["active"].connect (() => {
                verify_cf_banner.revealed = !verify_cf_row.active;
            });
            autostart_row.notify["active"].connect (() => {
                service.set_autostart (autostart_row.active);
            });
            save_row.activated.connect (save_settings);

#if ANDROID
            // The only status display on Android is the foreground-service
            // notification — no modes to pick. Keep the text template (it drives
            // the notification) and offer the system notification settings.
            status_display_group.visible = false;
            status_text_group.visible = true;
            notif_settings_row.visible = true;
            notif_settings_row.activated.connect (() => {
                var win = get_root () as Gtk.Window;
                if (win == null) return;
                var surface = win.get_surface ();
                if (surface != null) TgwsAndroid.open_notification_settings (surface);
            });
#else
            notif_settings_row.visible = false;
            setup_status_modes ();
#endif
        }

        private void setup_status_modes () {
            var p = Platform.get_default ();
            // Only available modes appear at all (no greyed-out toggles).
            add_mode_toggle ("window", _("Window"), true);
            add_mode_toggle ("tray", _("Tray"), p.tray_available ());
            add_mode_toggle ("background", _("Background"), p.background_portal_available ());
            add_mode_toggle ("quicksettings", _("Quick Settings"), p.extension_installed ());

            status_mode_group.active_name = p.resolve (cfg.status_mode).id ();
            update_text_visibility ();
            status_mode_group.notify["active-name"].connect (update_text_visibility);
        }

        private void add_mode_toggle (string name, string label, bool available) {
            if (!available) return;
            status_mode_group.add (new Adw.Toggle () { name = name, label = label });
        }

        private void update_text_visibility () {
            var m = StatusMode.from_id (status_mode_group.active_name ?? "window");
            status_text_group.visible = m != StatusMode.WINDOW;
        }

        private void save_settings () {
            cfg.host = host_row.text.strip ();
            cfg.port = (int) port_row.value;
            var sec = secret_row.text.strip ();
            if (sec.length == 32) cfg.secret = sec;
            cfg.dc_ip = dc_row.text.strip ().split (" ");
            cfg.cfproxy = cfproxy_row.active;
            cfg.verify_cf = verify_cf_row.active;
            cfg.pool_size = (int) pool_row.value;
            cfg.log_to_file = logfile_row.active;
            cfg.autostart = autostart_row.active;
            if (status_row.text.strip () != "") cfg.status_template = status_row.text.strip ();
            cfg.status_mode = status_mode_group.active_name ?? "auto";
            // The quick-settings mode is provided by the GNOME Shell extension —
            // enable it iff that mode is chosen, disable it for any other.
            var p = Platform.get_default ();
            if (p.extension_installed ())
                p.extension_set_enabled (cfg.status_mode == "quicksettings");
            cfg.save ();
            client.send ("reload");
            if (!service.is_active ()) service.start ();
            toast (_("Settings saved"));
        }
    }
}
