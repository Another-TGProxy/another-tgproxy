// SPDX-License-Identifier: GPL-3.0-or-later
namespace TgWsProxy {

    public class Application : Adw.Application {
#if DARWIN
        // The macOS menu-bar item lives in this (GTK) process — it pumps the AppKit
        // run loop — and outlives the window, so the app holds itself open for it.
        void* tray = null;
        DaemonClient? tray_client = null;
        ServiceController? tray_service = null;
        bool tray_running = false;
        string tray_link = "";
#endif

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
#if DARWIN
            setup_mac_tray ();
#endif
        }

        protected override void activate () {
            var win = this.active_window;
            if (win == null) {
                win = new Window (this);
            }
            win.present ();
#if ANDROID
            wire_battery_prompt (win);
#endif
        }

#if ANDROID
        bool battery_wired = false;
        bool battery_dialog_open = false;

        // A foreground service alone doesn't survive Doze / App Standby; nudge the
        // user to exempt the app from battery optimization. Checked every time the
        // window comes to the foreground (so it keeps asking until granted); by then
        // the surface is a realized Android toplevel, which the bridge needs.
        void wire_battery_prompt (Gtk.Window win) {
            if (battery_wired) return;
            battery_wired = true;
            win.notify["is-active"].connect (() => {
                if (!win.is_active) return;
                var surface = win.get_surface ();
                if (surface == null) return;
                // Cache the ProxyService class via the app class loader while we
                // have a surface, so the engine can later update the notification.
                TgwsAndroid.bind_notification (surface);
                if (battery_dialog_open) return;
                if (TgwsAndroid.is_ignoring_battery_optimizations (surface)) return;
                show_battery_dialog (win, surface);
            });
        }

        void show_battery_dialog (Gtk.Window win, Gdk.Surface surface) {
            battery_dialog_open = true;
            var dialog = new Adw.AlertDialog (
                _("Background operation"),
                _("To keep the proxy running in the background, disable battery optimization for this app. Otherwise Android may stop it after a while."));
            dialog.add_response ("later", _("Later"));
            dialog.add_response ("settings", _("Open settings"));
            dialog.set_response_appearance ("settings", Adw.ResponseAppearance.SUGGESTED);
            dialog.set_default_response ("settings");
            dialog.response.connect ((resp) => {
                battery_dialog_open = false;
                if (resp == "settings")
                    TgwsAndroid.request_ignore_battery_optimizations (surface);
            });
            dialog.present (win);
        }
#endif

#if DARWIN
        void setup_mac_tray () {
            var cfg = Config.load ();
            tray_service = new ServiceController (cfg);
            tray_client = new DaemonClient ();
            tray_client.status_changed.connect (on_tray_status);
            tray_client.start ();
            // The bundle's launcher points this at a template PNG of the app's
            // symbolic icon; empty in a dev run -> the shim falls back to a symbol.
            var icon = Environment.get_variable ("ANOTHER_TGPROXY_TRAY_ICON") ?? "";
            tray = Mac.tray_new (on_tray_action, icon,
                _("Open"), _("Open in Telegram"),
                _("Start"), _("Stop"), _("Restart"), _("Quit"));
            hold ();   // keep the menu-bar item alive after the window closes
        }

        void on_tray_status (Status s) {
            tray_running = s.running;
            if (s.secret.length == 32)
                tray_link = "tg://proxy?server=%s&port=%d&secret=dd%s".printf (
                    s.host, s.port, s.secret);
            if (tray != null)
                Mac.tray_update (tray,
                    s.running ? _("Another TGProxy — running")
                              : _("Another TGProxy — stopped"),
                    s.running ? 1 : 0);
        }

        void on_tray_action (int action) {
            switch (action) {
            case 0:   // Open
                activate ();
                break;
            case 1:   // Open in Telegram
                if (tray_link != "") {
                    try { AppInfo.launch_default_for_uri (tray_link, null); }
                    catch (Error e) { warning ("open telegram: %s", e.message); }
                }
                break;
            case 2:   // toggle start/stop
                if (tray_running) { tray_client.send ("stop"); tray_service.stop (); }
                else tray_service.start ();
                break;
            case 3:   // Restart
                tray_client.send ("reload");
                break;
            case 4:   // Quit
                tray_client.send ("stop");
                if (tray != null) { Mac.tray_free (tray); tray = null; }
                release ();
                quit ();
                break;
            }
        }
#endif
    }
}
