// SPDX-License-Identifier: GPL-3.0-or-later
// Minimal Vala GTK4/libadwaita app — validates Vala-on-Android via Pixiewood
// (valac runs on the host generating C, the NDK clang cross-compiles it against
// the Pixiewood-built GTK).
int main (string[] args) {
    var app = new Adw.Application ("space.ampernic.AdwDemo",
                                   ApplicationFlags.DEFAULT_FLAGS);
    app.activate.connect (() => {
        var win = new Adw.ApplicationWindow (app);
        win.title = "Adwaita Vala Demo";
        win.set_default_size (360, 640);

        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
            valign = Gtk.Align.CENTER
        };
        box.append (new Gtk.Label ("GTK4 + libadwaita"));
        box.append (new Gtk.Label ("Vala on Android"));

        var tv = new Adw.ToolbarView ();
        tv.add_top_bar (new Adw.HeaderBar ());
        tv.content = box;
        win.content = tv;
        win.present ();
    });
    return app.run (args);
}
