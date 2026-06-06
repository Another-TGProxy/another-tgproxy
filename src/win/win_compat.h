/* SPDX-License-Identifier: GPL-3.0-or-later */
#pragma once

/* Full path of the running executable (UTF-8, g_free the result). */
char *tgws_win_exe_path (void);

/* PID of the current process. */
int tgws_win_pid (void);
