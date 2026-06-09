// SPDX-License-Identifier: GPL-3.0-or-later
#if HAVE_QSHUB
namespace TgWsProxy {

    // A GNOME Quick Settings entry for the daemon, backed by libqshub. It registers
    // a menu toggle with the quick-settings-hub extension and exposes the app's
    // intents as signals, just like TrayController; the daemon wires them to the
    // engine. This replaces the app's own GNOME Shell extension - the hub builds
    // the real Quick Settings item from a declarative spec. Inert when no hub is
    // installed (the client stays a no-op and nothing appears).
    public class QshubController : Object {
        public signal void open_requested ();
        public signal void toggle_requested ();
        public signal void restart_requested ();
        public signal void open_telegram_requested ();
        public signal void quit_requested ();

        Qshub.Client? hub;
        Qshub.Item? item;
        // The app installs this symbolic icon as "<app-id>-symbolic" (see data/).
        string icon = "themed:" + Build.APP_ID_RELEVANT + "-symbolic";

        public QshubController () {
            hub = new Qshub.Client ();
            item = new Qshub.Item (Qshub.ItemType.MENU_TOGGLE, Build.APP_NAME);
            item.set_icon (icon);
            item.set_app (Build.APP_ID_RELEVANT, Build.APP_NAME);
            item.set_header (Build.APP_NAME, "", icon);
            item.add_menu_item ("open", _("Open"), "");
            item.add_menu_item ("open-telegram", _("Open in Telegram"), "");
            item.add_menu_item ("restart", _("Restart"), "");
            item.add_menu_item ("quit", _("Quit"), "");

            item.toggled.connect (() => toggle_requested ());
            item.menu_activated.connect ((id) => {
                if (id == "open") open_requested ();
                else if (id == "open-telegram") open_telegram_requested ();
                else if (id == "restart") restart_requested ();
                else if (id == "quit") quit_requested ();
            });

            hub.add (item);
        }

        public void update (string status, bool running) {
            if (item == null) return;
            item.set_checked (running);
            item.set_subtitle (status);
            item.set_header (Build.APP_NAME, status, icon);
        }

        // Drop the item from the hub and release the client.
        public void close () {
            if (hub != null && item != null) hub.remove (item);
            item = null;
            hub = null;
        }
    }
}
#endif
