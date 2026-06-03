// SPDX-License-Identifier: GPL-3.0-or-later
namespace TgWsProxy {

    public enum OsKind { LINUX, WINDOWS, MACOS, OTHER }

    public enum DeliveryKind { NATIVE, FLATPAK, SNAP, APPIMAGE }

    // How the proxy's live background status is surfaced to the user.
    public enum StatusMode {
        WINDOW,             // in-app only; the true everywhere fallback
        TRAY,               // StatusNotifierItem (SNI) tray / native notification area
        BACKGROUND_PORTAL,  // GNOME "Background Apps" (xdg portal, Flatpak only)
        QUICK_SETTINGS,     // GNOME Shell quick-settings toggle (needs our extension)
        NOTIFICATION;       // resident GNotification (weak on GNOME; future Android)

        public string id () {
            switch (this) {
                case WINDOW: return "window";
                case TRAY: return "tray";
                case BACKGROUND_PORTAL: return "background";
                case QUICK_SETTINGS: return "quicksettings";
                case NOTIFICATION: return "notification";
                default: return "window";
            }
        }

        public static StatusMode from_id (string id) {
            switch (id) {
                case "tray": return TRAY;
                case "background": return BACKGROUND_PORTAL;
                case "quicksettings": return QUICK_SETTINGS;
                case "notification": return NOTIFICATION;
                default: return WINDOW;
            }
        }
    }

    // Runtime detection of OS / desktop / delivery, and which status modes work here.
    public class Platform : Object {
        public OsKind os { get; private set; }
        public string desktop { get; private set; default = ""; }
        public bool is_gnome { get; private set; }
        public bool is_kde { get; private set; }
        public DeliveryKind delivery { get; private set; }
        public string session_type { get; private set; default = ""; }

        private static Platform? instance = null;

        public static Platform get_default () {
            if (instance == null) instance = new Platform ();
            return instance;
        }

        construct {
            switch (Build.OS) {
                case "linux": os = OsKind.LINUX; break;
                case "windows": os = OsKind.WINDOWS; break;
                case "darwin": os = OsKind.MACOS; break;
                default: os = OsKind.OTHER; break;
            }

            var xdg = Environment.get_variable ("XDG_CURRENT_DESKTOP") ?? "";
            foreach (var tok in xdg.split (":")) {
                var t = tok.up ();
                if (t == "GNOME") is_gnome = true;
                if (t == "KDE") is_kde = true;
                if (desktop == "" && t != "") desktop = t;
            }
            session_type = Environment.get_variable ("XDG_SESSION_TYPE") ?? "";

            if (FileUtils.test ("/.flatpak-info", FileTest.EXISTS)
                || Environment.get_variable ("FLATPAK_ID") != null)
                delivery = DeliveryKind.FLATPAK;
            else if (Environment.get_variable ("SNAP") != null)
                delivery = DeliveryKind.SNAP;
            else if (Environment.get_variable ("APPIMAGE") != null)
                delivery = DeliveryKind.APPIMAGE;
            else
                delivery = DeliveryKind.NATIVE;
        }

        // --- capabilities ---

        // A system tray exists: natively on Windows/macOS, or via a running
        // StatusNotifierItem host (KDE/XFCE/… or GNOME with the AppIndicator
        // extension) on Linux.
        public bool tray_available () {
            if (os == OsKind.WINDOWS || os == OsKind.MACOS) return true;
            if (os != OsKind.LINUX) return false;
            return dbus_name_owned ("org.kde.StatusNotifierWatcher");
        }

        // GNOME "Background Apps": xdg Background portal SetStatus is sandbox-only.
        public bool background_portal_available () {
            return os == OsKind.LINUX && is_gnome && delivery == DeliveryKind.FLATPAK;
        }

        // The quick-settings toggle is our GNOME Shell extension.
        public const string EXTENSION_UUID = "another-tgproxy@ampernic.space";

        public bool quick_settings_available () {
            return extension_installed ();
        }

        // --- GNOME Shell extension (the quick-settings toggle) ---

        public bool extension_installed () {
            var info = extension_info ();
            return info != null && info.contains ("uuid");
        }

        public bool extension_enabled () {
            var info = extension_info ();
            if (info == null) return false;
            var v = info.get ("enabled");
            return v != null && v.is_of_type (VariantType.BOOLEAN) && v.get_boolean ();
        }

        public void extension_set_enabled (bool on) {
            extension_call (on ? "EnableExtension" : "DisableExtension");
        }

        GLib.HashTable<string, Variant>? extension_info () {
            if (os != OsKind.LINUX || !is_gnome) return null;
            try {
                var conn = Bus.get_sync (BusType.SESSION);
                var r = conn.call_sync (
                    "org.gnome.Shell.Extensions", "/org/gnome/Shell/Extensions",
                    "org.gnome.Shell.Extensions", "GetExtensionInfo",
                    new Variant ("(s)", EXTENSION_UUID),
                    new VariantType ("(a{sv})"), DBusCallFlags.NONE, -1, null);
                Variant dict;
                r.get ("(@a{sv})", out dict);
                var h = new GLib.HashTable<string, Variant> (str_hash, str_equal);
                var it = dict.iterator ();
                string key;
                Variant val;
                while (it.next ("{sv}", out key, out val)) h.insert (key, val);
                return h;
            } catch (Error e) {
                return null;
            }
        }

        void extension_call (string method) {
            try {
                var conn = Bus.get_sync (BusType.SESSION);
                conn.call_sync (
                    "org.gnome.Shell.Extensions", "/org/gnome/Shell/Extensions",
                    "org.gnome.Shell.Extensions", method,
                    new Variant ("(s)", EXTENSION_UUID),
                    new VariantType ("(b)"), DBusCallFlags.NONE, -1, null);
            } catch (Error e) {
                warning ("extension %s failed: %s", method, e.message);
            }
        }

        // Reserved for Android (foreground-service ongoing notification). Not used
        // on desktop — GNOME has no persistent notification, only transient banners.
        public bool notification_available () {
            return false;
        }

        public StatusMode[] available_modes () {
            StatusMode[] m = { StatusMode.WINDOW };
            if (tray_available ()) m += StatusMode.TRAY;
            if (background_portal_available ()) m += StatusMode.BACKGROUND_PORTAL;
            if (quick_settings_available ()) m += StatusMode.QUICK_SETTINGS;
            if (notification_available ()) m += StatusMode.NOTIFICATION;
            return m;
        }

        // Best mode out of the box: tray where present, else the portal, else window.
        public StatusMode default_mode () {
            if (tray_available ()) return StatusMode.TRAY;
            if (background_portal_available ()) return StatusMode.BACKGROUND_PORTAL;
            return StatusMode.WINDOW;
        }

        // Resolve a stored preference ("auto" or a mode id) to a usable mode,
        // falling back to the default if the chosen one isn't available here.
        // Use this for the UI (which toggle to pre-select).
        public StatusMode resolve (string pref) {
            if (pref == "auto" || pref == "") return default_mode ();
            var want = StatusMode.from_id (pref);
            foreach (var m in available_modes ())
                if (m == want) return m;
            return default_mode ();
        }

        // Honor the stored mode literally ("auto" → default, else exactly the
        // chosen mode, no fallback). Use this to decide which presenter runs, so
        // selecting one mode never silently leaves another's presenter alive.
        public StatusMode mode_of (string pref) {
            if (pref == "auto" || pref == "") return default_mode ();
            return StatusMode.from_id (pref);
        }

        static bool dbus_name_owned (string name) {
            try {
                var conn = Bus.get_sync (BusType.SESSION);
                var r = conn.call_sync (
                    "org.freedesktop.DBus", "/org/freedesktop/DBus",
                    "org.freedesktop.DBus", "NameHasOwner",
                    new Variant ("(s)", name),
                    new VariantType ("(b)"), DBusCallFlags.NONE, -1, null);
                bool owned;
                r.get ("(b)", out owned);
                return owned;
            } catch (Error e) {
                return false;
            }
        }

        string os_name () {
            switch (os) {
                case OsKind.LINUX: return "linux";
                case OsKind.WINDOWS: return "windows";
                case OsKind.MACOS: return "macos";
                default: return "other";
            }
        }

        string delivery_name () {
            switch (delivery) {
                case DeliveryKind.FLATPAK: return "flatpak";
                case DeliveryKind.SNAP: return "snap";
                case DeliveryKind.APPIMAGE: return "appimage";
                default: return "native";
            }
        }

        public string describe () {
            var sb = new StringBuilder ();
            sb.append_printf ("os=%s desktop=%s gnome=%s kde=%s delivery=%s session=%s\n",
                os_name (), desktop, is_gnome.to_string (), is_kde.to_string (),
                delivery_name (), session_type);
            sb.append_printf ("tray=%s background=%s quicksettings=%s notification=%s\n",
                tray_available ().to_string (), background_portal_available ().to_string (),
                quick_settings_available ().to_string (), notification_available ().to_string ());
            sb.append ("modes:");
            foreach (var m in available_modes ()) sb.append (" " + m.id ());
            sb.append_printf ("\ndefault=%s\n", default_mode ().id ());
            return sb.str;
        }
    }
}
