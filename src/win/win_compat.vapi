// SPDX-License-Identifier: GPL-3.0-or-later
[CCode (cheader_filename = "win_compat.h")]
namespace Win {
    [CCode (cname = "tgws_win_exe_path")]
    public string exe_path ();
    [CCode (cname = "tgws_win_pid")]
    public int pid ();
}
