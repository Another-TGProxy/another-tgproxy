/* SPDX-License-Identifier: GPL-3.0-or-later */
[CCode (cheader_filename = "mac_tray.h")]
namespace Mac {
    [CCode (cname = "MacTrayCb", has_target = true)]
    public delegate void TrayCb (int action);

    [CCode (cname = "mac_tray_new")]
    public void* tray_new (TrayCb cb, string icon_path,
                           string l_open, string l_open_telegram,
                           string l_start, string l_stop,
                           string l_restart, string l_quit);

    [CCode (cname = "mac_tray_update")]
    public void tray_update (void* tray, string tooltip, int running);

    [CCode (cname = "mac_tray_free")]
    public void tray_free (void* tray);
}
