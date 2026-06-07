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
#if WINDOWS
        // The Shell_NotifyIcon tray lives in this GUI process (the headless daemon
        // has no message pump); the app holds itself open for it like on macOS.
        void* win_tray = null;
        DaemonClient? win_client = null;
        ServiceController? win_service = null;
        bool win_running = false;
        string win_link = "";
        bool win_close_hooked = false;
        bool win_quitting = false;
        // Set from main when launched with --minimized (autostart): start in the
        // tray with no window.
        public static bool start_minimized = false;
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
#if WINDOWS
            setup_win_tray ();
#endif
        }

        protected override void activate () {
#if WINDOWS
            // Autostart launch: stay in the tray, create no window until asked.
            if (start_minimized && this.active_window == null) {
                start_minimized = false;
                return;
            }
#endif
            var win = this.active_window;
            if (win == null) {
                win = new Window (this);
            }
#if ANDROID
            wire_android (win);   // before present() so we catch the first map
#endif
#if WINDOWS
            hook_win_close (win);   // close hides to tray instead of quitting
#endif
            win.present ();
        }

#if ANDROID
        static unowned Application? android_self = null;
        bool android_wired = false;
        bool battery_dialog_open = false;

        // "App opened / came back to the foreground" is an Android Activity
        // lifecycle event (onResume), not a GTK one: a quick home→reopen keeps the
        // surface mapped (only a relayout), so Gtk's map fires solely on the first
        // launch. So we drive the recurring check from ProxyApplication's
        // onActivityResumed via the bridge, and use the first map only to bind the
        // bridge (it needs a realized surface) and prompt on that initial launch.
        void wire_android (Gtk.Window win) {
            if (android_wired) return;
            android_wired = true;
            android_self = this;
            TgwsAndroid.set_resume_handler (android_resume);
            win.map.connect (() => {
                var surface = win.get_surface ();
                if (surface == null) return;
                TgwsAndroid.bind_notification (surface);
                check_battery (win);
            });
        }

        // Invoked on the GTK main thread on every activity resume.
        static void android_resume () {
            if (android_self == null) return;
            var win = android_self.active_window;
            if (win != null) android_self.check_battery (win);
        }

        void check_battery (Gtk.Window win) {
            if (battery_dialog_open) return;
            var surface = win.get_surface ();
            if (surface == null) return;
            if (TgwsAndroid.is_ignoring_battery_optimizations (surface)) return;
            show_battery_dialog (win, surface);
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
            // The daemon dropping (it quits on stop) means the proxy is gone; reset
            // the tray so the menu offers Start again.
            tray_client.connection_changed.connect ((connected) => {
                if (connected) return;
                tray_running = false;
                if (tray != null)
                    Mac.tray_update (tray, _("Another TGProxy — stopped"), 0);
            });
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

#if WINDOWS
        void setup_win_tray () {
            var cfg = Config.load ();
            win_service = new ServiceController (cfg);
            win_client = new DaemonClient ();
            win_client.status_changed.connect (on_win_tray_status);
            // The daemon dropping (it quits on stop) means the proxy is gone; reset
            // the tray so the menu offers Start again.
            win_client.connection_changed.connect ((connected) => {
                if (connected) return;
                win_running = false;
                if (win_tray != null)
                    Win.tray_update (win_tray, _("Another TGProxy — stopped"), 0);
            });
            win_client.start ();
            win_tray = Win.tray_new (on_win_tray_action,
                _("Open"), _("Open in Telegram"),
                _("Start"), _("Stop"), _("Restart"), _("Quit"));
            if (start_minimized)
                win_service.start ();   // autostart: bring the proxy up windowless
            hold ();   // keep the tray alive after the window closes
        }

        void on_win_tray_status (Status s) {
            win_running = s.running;
            if (s.secret.length == 32)
                win_link = "tg://proxy?server=%s&port=%d&secret=dd%s".printf (
                    s.host, s.port, s.secret);
            if (win_tray != null)
                Win.tray_update (win_tray,
                    s.running ? _("Another TGProxy — running")
                              : _("Another TGProxy — stopped"),
                    s.running ? 1 : 0);
        }

        void on_win_tray_action (int action) {
            switch (action) {
            case 0:   // Open
                activate ();
                break;
            case 1:   // Open in Telegram
                if (win_link != "")
                    Win.open_uri (win_link);   // GIO can't resolve tg:// on Windows
                break;
            case 2:   // toggle start/stop
                if (win_running) { win_client.send ("stop"); win_service.stop (); }
                else win_service.start ();
                break;
            case 3:   // Restart
                win_client.send ("reload");
                break;
            case 4:   // Quit
                win_quitting = true;
                win_client.send ("stop");
                if (win_tray != null) { Win.tray_free (win_tray); win_tray = null; }
                release ();
                quit ();
                break;
            }
        }

        // Closing the window hides it to the tray; the app keeps running. Quitting
        // from the tray sets win_quitting so the real close goes through.
        void hook_win_close (Gtk.Window win) {
            if (win_close_hooked) return;
            win_close_hooked = true;
            win.close_request.connect (() => {
                if (win_quitting) return false;
                win.set_visible (false);
                return true;
            });
        }
#endif
    }
}
