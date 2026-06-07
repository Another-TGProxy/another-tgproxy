// SPDX-License-Identifier: GPL-3.0-or-later
[CCode (cheader_filename = "win_compat.h")]
namespace Win {
    [CCode (cname = "tgws_win_exe_path")]
    public string exe_path ();
    [CCode (cname = "tgws_win_pid")]
    public int pid ();

    [CCode (cname = "TgwsTrayCb", has_target = true)]
    public delegate void TrayCb (int action);

    [CCode (cname = "tgws_tray_new")]
    public void* tray_new (TrayCb cb,
                           string l_open, string l_open_telegram,
                           string l_start, string l_stop,
                           string l_restart, string l_quit);

    [CCode (cname = "tgws_tray_update")]
    public void tray_update (void* tray, string tooltip, int running);

    [CCode (cname = "tgws_tray_free")]
    public void tray_free (void* tray);
}
