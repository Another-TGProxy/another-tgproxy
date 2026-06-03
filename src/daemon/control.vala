// SPDX-License-Identifier: GPL-3.0-or-later
namespace TgWsProxy {

    // D-Bus control surface for external front-ends (e.g. the GNOME Shell
    // quick-settings extension). Exported by the daemon at
    // /space/ampernic/AnotherTGProxy/Control on its application bus name.
    [DBus (name = "space.ampernic.AnotherTGProxy.Control1")]
    public class Control : Object {

        // Auto-properties notify on change → GDBus emits PropertiesChanged.
        [DBus (name = "Running")]
        public bool running { get; set; default = false; }
        [DBus (name = "Status")]
        public string status { get; set; default = ""; }

        // Explicit change notification (Vala doesn't reliably emit
        // PropertiesChanged for these), carrying the values for the consumer.
        [DBus (name = "Changed")]
        public signal void changed (bool running, string status);

        [DBus (visible = false)]
        public void publish (bool r, string s) {
            running = r;
            status = s;
            changed (r, s);
        }

        [DBus (visible = false)] public signal void toggle_requested ();
        [DBus (visible = false)] public signal void restart_requested ();
        [DBus (visible = false)] public signal void open_requested ();
        [DBus (visible = false)] public signal void open_telegram_requested ();
        [DBus (visible = false)] public signal void quit_requested ();

        [DBus (name = "Toggle")]
        public void toggle () throws DBusError, IOError { toggle_requested (); }
        [DBus (name = "Restart")]
        public void restart () throws DBusError, IOError { restart_requested (); }
        [DBus (name = "Open")]
        public void open () throws DBusError, IOError { open_requested (); }
        [DBus (name = "OpenTelegram")]
        public void open_telegram () throws DBusError, IOError { open_telegram_requested (); }
        [DBus (name = "Quit")]
        public void quit () throws DBusError, IOError { quit_requested (); }
    }
}
