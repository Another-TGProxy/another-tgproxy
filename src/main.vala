// SPDX-License-Identifier: GPL-3.0-or-later
int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "");
#if WINDOWS
    // No system CA store path on Windows; the engine's TLS verify (CF domains)
    // reads SSL_CERT_FILE first, so point it at the CA bundle shipped next to the
    // .exe (<dir>/ssl/certs/ca-bundle.crt) unless the user already set one.
    if (Environment.get_variable ("SSL_CERT_FILE") == null) {
        var ca = Path.build_filename (
            Path.get_dirname (Win.exe_path ()), "ssl", "certs", "ca-bundle.crt");
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
#if WINDOWS
    // Autostart entry passes --minimized: start in the tray. Strip it so it
    // doesn't reach GApplication's option handling.
    string[] filtered = {};
    foreach (var a in args) {
        if (a == "--minimized") TgWsProxy.Application.start_minimized = true;
        else filtered += a;
    }
    args = filtered;
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