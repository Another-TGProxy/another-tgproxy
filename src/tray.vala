// SPDX-License-Identifier: GPL-3.0-or-later
namespace TgWsProxy {

    // The system-tray status icon + menu, backed by libstation's Station.Tray
    // (StatusNotifierItem on Linux, NSStatusItem on macOS, Shell_NotifyIcon on
    // Windows). It exposes the app's intents as signals; the daemon (Linux) or the
    // GUI process (macOS/Windows) wires them to the engine / service controller.
    public class TrayController : Object {
        public signal void open_requested ();
        public signal void toggle_requested ();
        public signal void restart_requested ();
        public signal void open_telegram_requested ();
        public signal void quit_requested ();

        Station.Tray? tray;
        uint id_status;
        uint id_open;
        uint id_open_tg;
        uint id_toggle;
        uint id_restart;
        uint id_quit;

        // icon_file: an image file for the icon (macOS/Windows); empty falls back
        // to the themed icon name (Linux) or the exe's embedded icon (Windows).
        public TrayController (string icon_file = "") {
            tray = new Station.Tray (Build.APP_ID_RELEVANT);
            tray.set_icon_name (Build.APP_ID_RELEVANT);
            if (icon_file != "")
                tray.set_icon_file (icon_file);
            tray.set_tooltip (Build.APP_NAME);

            // A non-interactive status header, then the actions.
            id_status = tray.add_item ("—");
            tray.set_item_enabled (id_status, false);
            tray.add_separator ();
            id_open = tray.add_item (_("Open"));
            id_open_tg = tray.add_item (_("Open in Telegram"));
            tray.add_separator ();
            id_toggle = tray.add_item (_("Start"));
            id_restart = tray.add_item (_("Restart"));
            tray.add_separator ();
            id_quit = tray.add_item (_("Quit"));

            tray.activate.connect (() => open_requested ());
            tray.activated.connect ((id) => {
                if (id == id_open) open_requested ();
                else if (id == id_open_tg) open_telegram_requested ();
                else if (id == id_toggle) toggle_requested ();
                else if (id == id_restart) restart_requested ();
                else if (id == id_quit) quit_requested ();
            });
        }

        public void update (string tooltip, bool running) {
            if (tray == null) return;
            tray.set_tooltip (tooltip);
            tray.set_item_label (id_status, tooltip == "" ? "—" : tooltip);
            tray.set_item_label (id_toggle, running ? _("Stop") : _("Start"));
        }

        // Drop the icon: releasing the last ref finalizes Station.Tray, which
        // removes it from the status area.
        public void close () {
            tray = null;
        }
    }
}
