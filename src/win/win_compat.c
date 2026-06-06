/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "win_compat.h"
#include <windows.h>
#include <glib.h>

char *
tgws_win_exe_path (void)
{
  wchar_t buf[32768];
  DWORD n = GetModuleFileNameW (NULL, buf, G_N_ELEMENTS (buf));
  if (n == 0 || n >= G_N_ELEMENTS (buf))
    return g_strdup ("another-tgproxy.exe");
  return g_utf16_to_utf8 ((const gunichar2 *) buf, -1, NULL, NULL, NULL);
}

int
tgws_win_pid (void)
{
  return (int) GetCurrentProcessId ();
}
