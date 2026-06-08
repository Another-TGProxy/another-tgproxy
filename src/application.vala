// SPDX-License-Identifier: GPL-3.0-or-later
namespace TgWsProxy {

    public class Application : Adw.Application {
#if DARWIN || WINDOWS
        // On macOS/Windows the native tray (NSStatusItem / Shell_NotifyIcon, via
        // libstation) must live in this GUI process — it needs the AppKit run loop
        // / the thread message pump — and outlives the window, so the app holds
        // itself open for it. The daemon (controlled over IPC) does the proxying.
        TrayController? tray = null;
        DaemonClient? tray_client = null;
        ServiceController? tray_service = null;
        bool tray_running = false;
        string tray_link = "";
#endif
#if WINDOWS
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
#if DARWIN || WINDOWS
            setup_tray ();
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
            // A re-activation with a window already up means a second launch tried
            // to start (forwarded here) — surface a "already running" note.
            bool was_open = (this.active_window != null);
            present_window ();
#if WINDOWS || DARWIN
            if (was_open)
                show_already_running ();
#endif
        }

        // Create the window if needed and bring it to the front (no warning); used
        // for the normal launch and for the tray "Open" action.
        public void present_window () {
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

#if WINDOWS || DARWIN
        void show_already_running () {
            var win = this.active_window;
            if (win == null)
                return;
            var dlg = new Adw.AlertDialog (
                _("Already running"),
                _("Another TGProxy is already open."));
            dlg.add_response ("ok", _("OK"));
            dlg.set_default_response ("ok");
            dlg.present (win);
        }
#endif

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
            Station.android_set_resume_handler (android_resume);
            win.map.connect (() => {
                var surface = win.get_surface ();
                if (surface == null) return;
                Station.android_foreground_bind (surface,
                    "space.ampernic.anothertgproxy.ProxyApplication",
                    "space.ampernic.anothertgproxy.ProxyService");
                // Android 13+: the foreground-service notification (our status
                // display) needs the POST_NOTIFICATIONS runtime grant.
                Station.android_request_notification_permission (surface);
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
            if (Station.android_battery_unrestricted (surface)) return;
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
                    Station.android_request_battery_unrestricted (surface);
            });
            dialog.present (win);
        }
#endif

#if DARWIN || WINDOWS
        // The tray runs in the GUI process and controls the daemon over IPC.
        void setup_tray () {
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
                    tray.update (_("Another TGProxy — stopped"), false);
            });
            tray_client.start ();
            // The macOS bundle launcher points this at a template PNG of the app's
            // symbolic icon; empty elsewhere -> themed/embedded icon fallback.
            var icon = Environment.get_variable ("ANOTHER_TGPROXY_TRAY_ICON") ?? "";
            tray = new TrayController (icon);
            tray.open_requested.connect (() => present_window ());
            tray.open_telegram_requested.connect (() => {
                if (tray_link == "") return;
                // libstation resolves tg:// natively (GIO can't on Windows).
                try { Station.open_uri (tray_link); }
                catch (Error e) { warning ("open telegram: %s", e.message); }
            });
            tray.toggle_requested.connect (() => {
                if (tray_running) { tray_client.send ("stop"); tray_service.stop (); }
                else tray_service.start ();
            });
            tray.restart_requested.connect (() => tray_client.send ("reload"));
            tray.quit_requested.connect (() => {
#if WINDOWS
                win_quitting = true;
#endif
                tray_client.send ("stop");
                if (tray != null) { tray.close (); tray = null; }
                release ();
                quit ();
            });
#if WINDOWS
            if (start_minimized)
                tray_service.start ();   // autostart: bring the proxy up windowless
#endif
            hold ();   // keep the tray alive after the window closes
        }

        void on_tray_status (Status s) {
            tray_running = s.running;
            if (s.secret.length == 32)
                tray_link = "tg://proxy?server=%s&port=%d&secret=dd%s".printf (
                    s.host, s.port, s.secret);
            if (tray != null)
                tray.update (
                    s.running ? _("Another TGProxy — running")
                              : _("Another TGProxy — stopped"),
                    s.running);
        }
#endif

#if WINDOWS
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
