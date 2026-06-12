// SPDX-License-Identifier: GPL-3.0-or-later
int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "");
#if WINDOWS
    // No system CA store path on Windows; the engine's TLS verify (CF domains)
    // reads SSL_CERT_FILE first, so point it at the CA bundle shipped next to the
    // .exe (<dir>/ssl/certs/ca-bundle.crt) unless the user already set one.
    if (Environment.get_variable ("SSL_CERT_FILE") == null) {
        var ca = Path.build_filename (
            Path.get_dirname (Station.get_executable_path () ?? ""), "ssl", "certs", "ca-bundle.crt");
        if (FileUtils.test (ca, FileTest.EXISTS))
            Environment.set_variable ("SSL_CERT_FILE", ca, true);
    }
#endif
    // Inside an AppImage the install prefix is the (relocatable) mount point, so
    // the baked-in LOCALEDIR doesn't exist; $APPDIR points at the bundle root.
    string localedir = Build.LOCALEDIR;
    var appdir = Environment.get_variable ("APPDIR");
    if (appdir != null && appdir != "")
        localedir = appdir + "/usr/share/locale";
#if ANDROID
    // The catalogs ship under the extracted assets, which gdk-android exposes as
    // XDG_DATA_DIRS (<filesDir>/share); the baked-in absolute LOCALEDIR is wrong.
    var data_dirs = Environment.get_system_data_dirs ();
    if (data_dirs.length > 0)
        localedir = Path.build_filename (data_dirs[0], "locale");
#endif
#if WINDOWS
    // Relocatable bundle: the baked-in LOCALEDIR is the CI build prefix. Resolve
    // the catalogs next to the exe — <root>/share/locale (exe lives in <root>/bin).
    var win_root = Path.get_dirname (Path.get_dirname (Station.get_executable_path () ?? ""));
    localedir = Path.build_filename (win_root, "share", "locale");
    // Point GIO at the bundled modules (glib-networking, the TLS backend the
    // update check needs over HTTPS) — the baked-in module dir is the CI prefix.
    Environment.set_variable ("GIO_EXTRA_MODULES",
        Path.build_filename (win_root, "lib", "gio", "modules"), true);
#endif
#if DARWIN
    // Relocatable .app: catalogs live in Contents/Resources/locale (the binary is
    // in Contents/MacOS), not at the baked-in build-prefix LOCALEDIR.
    var mac_res = Path.build_filename (
        Path.get_dirname (Path.get_dirname (Station.get_executable_path () ?? "")),
        "Resources");
    localedir = Path.build_filename (mac_res, "locale");
#endif
    // Flatpak: the development profile bakes the build-tree po dir into LOCALEDIR
    // (so `meson devenv` finds catalogs uninstalled), but inside the installed
    // sandbox the .mo lives at /app/share/locale. A release build already resolves
    // there, so this is a no-op for it.
    if (Environment.get_variable ("FLATPAK_ID") != null)
        localedir = "/app/share/locale";
    Intl.bindtextdomain (Build.GETTEXT_PACKAGE, localedir);
    Intl.bind_textdomain_codeset (Build.GETTEXT_PACKAGE, "UTF-8");
    Intl.textdomain (Build.GETTEXT_PACKAGE);

    if (args.length > 1 && args[1] == "--ctest") {
        return TgWsProxy.engine_selftest ();  // C engine crypto/handshake self-check
    }
    if (args.length > 1 && args[1] == "--platform-info") {
        print ("%s", TgWsProxy.Platform.get_default ().describe ());
        return 0;
    }
    if (args.length > 1 && args[1] == "--proxy") {
        return TgWsProxy.run_proxy (args);    // headless C engine relay
    }
#if !ANDROID
    if (args.length > 1 && args[1] == "--daemon") {
        return TgWsProxy.run_daemon (args);   // background daemon + control IPC
    }
#endif
    Environment.set_application_name (Build.APP_NAME);
    Adw.init ();
    // GTK and libadwaita bind their own gettext domains to the baked-in LOCALEDIR
    // during init; in a relocatable bundle that path is the build prefix, so stock
    // widget strings (e.g. the About dialog's Developer/Website labels) fall back
    // to English. Re-point those domains at the bundled catalogs — after init, so
    // this binding is the one that sticks.
    bool bundled = appdir != null && appdir != "";
#if WINDOWS || ANDROID || DARWIN
    bundled = true;
#endif
    if (bundled) {
        Intl.bindtextdomain ("gtk40", localedir);
        Intl.bind_textdomain_codeset ("gtk40", "UTF-8");
        Intl.bindtextdomain ("libadwaita", localedir);
        Intl.bind_textdomain_codeset ("libadwaita", "UTF-8");
    }
#if WINDOWS
    // Autostart entry passes --minimized: start in the tray. Strip it so it
    // doesn't reach GApplication's option handling.
    string[] filtered = {};
    foreach (var a in args) {
        if (a == "--minimized") TgWsProxy.Application.start_minimized = true;
        else filtered += a;
    }
    args = filtered;
    // GApplication's uniqueness needs a D-Bus session bus, absent on MSYS2/Windows,
    // so guard explicitly: a second launch asks the running app to come forward
    // (present its window, even from the tray) and exits.
    if (!Station.single_instance_acquire (Build.APP_ID_RELEVANT, () => {
            var running = GLib.Application.get_default ();
            if (running != null) running.activate ();
        })) {
        return 0;
    }
#endif
    var app = new TgWsProxy.Application ();
    return app.run (args);
}

namespace TgWsProxy {

    static uint8[] from_hex (string s) {
        var r = new uint8[s.length / 2];
        for (int i = 0; i < r.length; i++)
            r[i] = (uint8) ((s[2 * i].xdigit_value () << 4) | s[2 * i + 1].xdigit_value ());
        return r;
    }

    // Headless relay using the C engine. Usage:
    //   another-tgproxy --proxy [SECRET_HEX] [HOST] [PORT]
    public int run_proxy (string[] args) {
        string secret_hex = (args.length > 2) ? args[2]
                                              : "3313d0b0af25df7e15eb02d1b856434b";
        string host = (args.length > 3) ? args[3] : "127.0.0.1";
        uint16 port = (uint16) ((args.length > 4) ? int.parse (args[4]) : 1443);

        if (secret_hex.length != 32) {
            stderr.printf ("secret must be 32 hex chars\n");
            return 1;
        }
        var secret = from_hex (secret_hex);

        var engine = new Engine (host, port, secret);
        engine.add_dc (2, "149.154.167.220");
        engine.add_dc (4, "149.154.167.220");
        if (!engine.start ()) {
            stderr.printf ("failed to start proxy on %s:%u\n", host, port);
            return 1;
        }
        print ("tg://proxy?server=%s&port=%u&secret=dd%s\n", host, port, secret_hex);

        var loop = new MainLoop ();
        loop.run ();
        return 0;
    }
}