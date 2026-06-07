/* SPDX-License-Identifier: GPL-3.0-or-later */
#pragma once

/* Full path of the running executable (UTF-8, g_free the result). */
char *tgws_win_exe_path (void);

/* PID of the current process. */
int tgws_win_pid (void);

/* Open a URI with the system default handler (ShellExecute). GIO's
 * launch_default_for_uri doesn't resolve custom schemes like tg:// on Windows. */
void tgws_win_open_uri (const char *uri);

/* System-tray icon (Shell_NotifyIcon) with a right-click menu, living in the GUI
 * process. The callback fires on the GTK main thread; action: 0 open, 1 open in
 * Telegram, 2 toggle start/stop, 3 restart, 4 quit. Labels are UTF-8. */
typedef void (*TgwsTrayCb) (int action, void *user_data);

void *tgws_tray_new (TgwsTrayCb cb, void *user_data,
                     const char *l_open, const char *l_open_telegram,
                     const char *l_start, const char *l_stop,
                     const char *l_restart, const char *l_quit);
void tgws_tray_update (void *tray, const char *tooltip, int running);
void tgws_tray_free (void *tray);
