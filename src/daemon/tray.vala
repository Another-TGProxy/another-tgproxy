// SPDX-License-Identifier: GPL-3.0-or-later
namespace TgWsProxy {

    public struct IconPixmap {
        int width;
        int height;
        uint8[] bytes;
    }

    public struct SniToolTip {
        string icon_name;
        IconPixmap[] pixmaps;
        string title;
        string description;
    }

    public struct MenuItemProps {
        int id;
        GLib.HashTable<string, Variant> props;
    }

    public struct MenuRemovedProps {
        int id;
        string[] props;
    }

    // Maps to the dbusmenu layout tuple (ia{sv}av): id, properties, children
    // (each child is a Variant wrapping another such tuple).
    public struct MenuLayout {
        int id;
        GLib.HashTable<string, Variant> props;
        Variant[] children;
    }

    // org.kde.StatusNotifierItem — the tray icon itself.
    [DBus (name = "org.kde.StatusNotifierItem")]
    public class SniItem : Object {
        public string tooltip_title = "";
        public string tooltip_text = "";
        public string icon = "";

        [DBus (visible = false)]
        public signal void primary ();
        [DBus (visible = false)]
        public signal void secondary ();

        [DBus (name = "Category")]
        public string category { owned get { return "ApplicationStatus"; } }
        [DBus (name = "Id")]
        public string item_id { owned get { return Build.APP_ID_RELEVANT; } }
        [DBus (name = "Title")]
        public string item_title { owned get { return tooltip_title; } }
        [DBus (name = "Status")]
        public string item_status { owned get { return "Active"; } }
        [DBus (name = "IconName")]
        public string icon_name { owned get { return icon; } }
        [DBus (name = "ItemIsMenu")]
        public bool item_is_menu { get { return true; } }
        [DBus (name = "Menu")]
        public ObjectPath menu_path { owned get { return new ObjectPath ("/MenuBar"); } }

        [DBus (name = "ToolTip")]
        public SniToolTip tool_tip {
            owned get {
                return SniToolTip () {
                    icon_name = icon,
                    pixmaps = new IconPixmap[0],
                    title = tooltip_title,
                    description = tooltip_text
                };
            }
        }

        [DBus (name = "NewIcon")]
        public signal void new_icon ();
        [DBus (name = "NewToolTip")]
        public signal void new_tool_tip ();
        [DBus (name = "NewStatus")]
        public signal void new_status (string s);

        [DBus (name = "Activate")]
        public void activate (int x, int y) throws DBusError, IOError { primary (); }
        [DBus (name = "SecondaryActivate")]
        public void secondary_activate (int x, int y) throws DBusError, IOError { primary (); }
        [DBus (name = "ContextMenu")]
        public void context_menu (int x, int y) throws DBusError, IOError { secondary (); }
        [DBus (name = "Scroll")]
        public void scroll (int delta, string orientation) throws DBusError, IOError { }
    }

    // com.canonical.dbusmenu — the right-click menu for the tray item.
    [DBus (name = "com.canonical.dbusmenu")]
    public class DBusMenu : Object {
        [DBus (visible = false)]
        public signal void clicked (int id);

        bool running = false;
        string status_text = "";
        uint revision = 2;

        [DBus (name = "Version")]
        public uint version { get { return 3; } }
        [DBus (name = "Status")]
        public string status { owned get { return "normal"; } }
        [DBus (name = "TextDirection")]
        public string text_direction { owned get { return "ltr"; } }

        // Set the running state; returns true (and bumps the revision) if changed.
        [DBus (visible = false)]
        public bool set_running (bool r) {
            if (r == running) return false;
            running = r;
            revision++;
            return true;
        }

        [DBus (visible = false)]
        public uint current_revision () { return revision; }

        // Update the non-interactive status header in place (no full re-layout).
        [DBus (visible = false)]
        public void update_status (string s) {
            if (s == status_text) return;
            status_text = s;
            items_properties_updated (
                { MenuItemProps () { id = 8, props = props_for (8) } },
                new MenuRemovedProps[0]);
        }

        // Single source of truth for an item's properties (used by both
        // GetLayout and GetGroupProperties).
        GLib.HashTable<string, Variant> props_for (int id) {
            var h = new GLib.HashTable<string, Variant> (str_hash, str_equal);
            h.insert ("visible", new Variant.boolean (true));
            switch (id) {
                case 8:
                    h.insert ("label", new Variant.string (status_text == "" ? "—" : status_text));
                    h.insert ("enabled", new Variant.boolean (false));
                    break;
                case 9:
                    h.insert ("type", new Variant.string ("separator"));
                    break;
                case 1:
                    h.insert ("label", new Variant.string (_("Open")));
                    h.insert ("enabled", new Variant.boolean (true));
                    break;
                case 7:
                    h.insert ("label", new Variant.string (_("Open in Telegram")));
                    h.insert ("enabled", new Variant.boolean (true));
                    break;
                case 2:
                case 4:
                    h.insert ("type", new Variant.string ("separator"));
                    break;
                case 3:
                    h.insert ("label", new Variant.string (running ? _("Stop") : _("Start")));
                    h.insert ("enabled", new Variant.boolean (true));
                    break;
                case 6:
                    h.insert ("label", new Variant.string (_("Restart")));
                    h.insert ("enabled", new Variant.boolean (true));
                    break;
                case 5:
                    h.insert ("label", new Variant.string (_("Quit")));
                    h.insert ("enabled", new Variant.boolean (true));
                    break;
            }
            return h;
        }

        Variant node (int id) {
            var pb = new VariantBuilder (new VariantType ("a{sv}"));
            props_for (id).foreach ((k, v) => { pb.add ("{sv}", k, v); });
            var kids = new VariantBuilder (new VariantType ("av"));
            return new Variant ("(ia{sv}av)", id, pb, kids);
        }

        MenuLayout layout () {
            Variant[] kids = {};
            foreach (int id in new int[] { 8, 9, 1, 7, 2, 3, 6, 4, 5 })
                kids += node (id);
            var rp = new GLib.HashTable<string, Variant> (str_hash, str_equal);
            rp.insert ("children-display", new Variant.string ("submenu"));
            return MenuLayout () { id = 0, props = rp, children = kids };
        }

        [DBus (name = "GetLayout")]
        public void get_layout (int parent_id, int recursion_depth, string[] property_names,
                                out uint rev, out MenuLayout lay) throws DBusError, IOError {
            rev = revision;
            lay = layout ();
        }

        [DBus (name = "GetGroupProperties")]
        public void get_group_properties (int[] ids, string[] property_names,
                                          out MenuItemProps[] props) throws DBusError, IOError {
            int[] want = ids.length > 0 ? ids : new int[] { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
            MenuItemProps[] list = {};
            foreach (int id in want)
                list += MenuItemProps () { id = id, props = props_for (id) };
            props = list;
        }

        [DBus (name = "GetProperty")]
        public Variant get_property_ (int id, string name) throws DBusError, IOError {
            var h = props_for (id);
            return h.contains (name) ? h.get (name) : new Variant.boolean (false);
        }

        [DBus (name = "Event")]
        public void event (int id, string event_id, Variant data, uint timestamp)
                throws DBusError, IOError {
            if (event_id == "clicked") clicked (id);
        }

        [DBus (name = "AboutToShow")]
        public bool about_to_show (int id) throws DBusError, IOError { return false; }

        [DBus (name = "LayoutUpdated")]
        public signal void layout_updated (uint rev, int parent);
        [DBus (name = "ItemsPropertiesUpdated")]
        public signal void items_properties_updated (MenuItemProps[] updated,
                                                     MenuRemovedProps[] removed);
        [DBus (name = "ItemActivationRequested")]
        public signal void item_activation_requested (int id, uint timestamp);
    }

    // Owns the SNI item + menu, registers with the watcher, exposes intents.
    public class TrayStatus : Object {
        public signal void open_requested ();
        public signal void toggle_requested ();
        public signal void restart_requested ();
        public signal void open_telegram_requested ();
        public signal void quit_requested ();

        const string WATCHER = "org.kde.StatusNotifierWatcher";

        DBusConnection conn;
        SniItem item;
        DBusMenu menu;
        string bus_name;
        uint owner_id = 0;
        uint item_reg = 0;
        uint menu_reg = 0;
        uint watch = 0;

        public TrayStatus () {
            try {
                conn = Bus.get_sync (BusType.SESSION);
            } catch (Error e) {
                warning ("tray: no session bus: %s", e.message);
                return;
            }
            item = new SniItem () { icon = Build.APP_ID_RELEVANT };
            menu = new DBusMenu ();

            item.primary.connect (() => open_requested ());
            item.secondary.connect (() => open_requested ());
            menu.clicked.connect ((id) => {
                if (id == 1) open_requested ();
                else if (id == 7) open_telegram_requested ();
                else if (id == 3) toggle_requested ();
                else if (id == 6) restart_requested ();
                else if (id == 5) quit_requested ();
            });

            bus_name = "org.kde.StatusNotifierItem-%d-1".printf ((int) Posix.getpid ());
            owner_id = Bus.own_name_on_connection (conn, bus_name,
                BusNameOwnerFlags.NONE,
                (c) => { on_acquired (); },
                (c) => { });
            watch = Bus.watch_name (BusType.SESSION, WATCHER,
                BusNameWatcherFlags.NONE,
                (c, n, owner) => { register_item (); },
                (c, n) => { });
        }

        void on_acquired () {
            try {
                item_reg = conn.register_object ("/StatusNotifierItem", item);
                menu_reg = conn.register_object ("/MenuBar", menu);
            } catch (Error e) {
                warning ("tray: register failed: %s", e.message);
                return;
            }
            register_item ();
        }

        void register_item () {
            if (item_reg == 0) return;
            conn.call.begin (WATCHER, "/StatusNotifierWatcher",
                WATCHER, "RegisterStatusNotifierItem",
                new Variant ("(s)", bus_name),
                null, DBusCallFlags.NONE, -1, null);
        }

        public void update (string tooltip, bool running) {
            if (item == null) return;
            item.tooltip_title = Build.APP_NAME;
            item.tooltip_text = tooltip;
            item.new_tool_tip ();
            menu.update_status (tooltip);
            if (menu.set_running (running))
                menu.layout_updated (menu.current_revision (), 0);
        }

        public void close () {
            if (item_reg != 0) { conn.unregister_object (item_reg); item_reg = 0; }
            if (menu_reg != 0) { conn.unregister_object (menu_reg); menu_reg = 0; }
            if (owner_id != 0) { Bus.unown_name (owner_id); owner_id = 0; }
            if (watch != 0) { Bus.unwatch_name (watch); watch = 0; }
        }
    }
}
