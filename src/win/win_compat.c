/* SPDX-License-Identifier: GPL-3.0-or-later */
/* Use the wide Win32 API: the generic macros (IDI_APPLICATION, MAKEINTRESOURCE,
 * …) then resolve to their W forms, matching the explicit *W calls below. */
#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include "win_compat.h"
#include <windows.h>
#include <shellapi.h>
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

/* ---- system-tray icon ---- */

#define TGWS_TRAY_MSG (WM_APP + 1)
enum { ID_OPEN = 1, ID_OPEN_TG, ID_TOGGLE, ID_RESTART, ID_QUIT };

typedef struct
{
  HWND hwnd;
  NOTIFYICONDATAW nid;
  TgwsTrayCb cb;
  void *user;
  int running;
  wchar_t *open, *open_tg, *start, *stop, *restart, *quit;
} TgwsTray;

static wchar_t *
to_w (const char *s)
{
  return (wchar_t *) g_utf8_to_utf16 (s ? s : "", -1, NULL, NULL, NULL);
}

static void
tray_popup (TgwsTray *t)
{
  HMENU m = CreatePopupMenu ();
  AppendMenuW (m, MF_STRING, ID_OPEN, t->open);
  AppendMenuW (m, MF_STRING, ID_OPEN_TG, t->open_tg);
  AppendMenuW (m, MF_SEPARATOR, 0, NULL);
  AppendMenuW (m, MF_STRING, ID_TOGGLE, t->running ? t->stop : t->start);
  AppendMenuW (m, MF_STRING, ID_RESTART, t->restart);
  AppendMenuW (m, MF_SEPARATOR, 0, NULL);
  AppendMenuW (m, MF_STRING, ID_QUIT, t->quit);

  POINT p;
  GetCursorPos (&p);
  /* Required so the menu dismisses on click-away (Win32 quirk). */
  SetForegroundWindow (t->hwnd);
  int cmd = TrackPopupMenu (m, TPM_RIGHTBUTTON | TPM_RETURNCMD,
                            p.x, p.y, 0, t->hwnd, NULL);
  PostMessageW (t->hwnd, WM_NULL, 0, 0);
  DestroyMenu (m);

  if (!cmd)
    return;
  int action = -1;
  switch (cmd) {
  case ID_OPEN: action = 0; break;
  case ID_OPEN_TG: action = 1; break;
  case ID_TOGGLE: action = 2; break;
  case ID_RESTART: action = 3; break;
  case ID_QUIT: action = 4; break;
  }
  if (action >= 0 && t->cb)
    t->cb (action, t->user);
}

static LRESULT CALLBACK
tray_wndproc (HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
  TgwsTray *t = (TgwsTray *) GetWindowLongPtrW (hwnd, GWLP_USERDATA);
  if (t != NULL && msg == TGWS_TRAY_MSG) {
    if (LOWORD (lp) == WM_LBUTTONUP || LOWORD (lp) == WM_LBUTTONDBLCLK) {
      if (t->cb)
        t->cb (0, t->user); /* open */
    } else if (LOWORD (lp) == WM_RBUTTONUP || LOWORD (lp) == WM_CONTEXTMENU) {
      tray_popup (t);
    }
    return 0;
  }
  return DefWindowProcW (hwnd, msg, wp, lp);
}

static HICON
tray_icon (void)
{
  HMODULE self = GetModuleHandleW (NULL);
  /* Icon id 1 from the linked resource (data/windows/another-tgproxy.rc). */
  HICON ic = (HICON) LoadImageW (self, MAKEINTRESOURCEW (1), IMAGE_ICON,
                                 GetSystemMetrics (SM_CXSMICON),
                                 GetSystemMetrics (SM_CYSMICON), LR_DEFAULTCOLOR);
  if (ic == NULL)
    ic = LoadIconW (NULL, IDI_APPLICATION);
  return ic;
}

void *
tgws_tray_new (TgwsTrayCb cb, void *user_data,
               const char *l_open, const char *l_open_telegram,
               const char *l_start, const char *l_stop,
               const char *l_restart, const char *l_quit)
{
  static const wchar_t *CLASS = L"TgwsTrayWindow";
  HINSTANCE inst = GetModuleHandleW (NULL);

  static gsize cls_once = 0;
  if (g_once_init_enter (&cls_once)) {
    WNDCLASSEXW wc = { 0 };
    wc.cbSize = sizeof (wc);
    wc.lpfnWndProc = tray_wndproc;
    wc.hInstance = inst;
    wc.lpszClassName = CLASS;
    RegisterClassExW (&wc);
    g_once_init_leave (&cls_once, 1);
  }

  TgwsTray *t = g_new0 (TgwsTray, 1);
  t->cb = cb;
  t->user = user_data;
  t->open = to_w (l_open);
  t->open_tg = to_w (l_open_telegram);
  t->start = to_w (l_start);
  t->stop = to_w (l_stop);
  t->restart = to_w (l_restart);
  t->quit = to_w (l_quit);

  t->hwnd = CreateWindowExW (0, CLASS, L"", 0, 0, 0, 0, 0,
                             HWND_MESSAGE, NULL, inst, NULL);
  if (t->hwnd == NULL) {
    tgws_tray_free (t);
    return NULL;
  }
  SetWindowLongPtrW (t->hwnd, GWLP_USERDATA, (LONG_PTR) t);

  t->nid.cbSize = sizeof (t->nid);
  t->nid.hWnd = t->hwnd;
  t->nid.uID = 1;
  t->nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  t->nid.uCallbackMessage = TGWS_TRAY_MSG;
  t->nid.hIcon = tray_icon ();
  Shell_NotifyIconW (NIM_ADD, &t->nid);
  return t;
}

void
tgws_tray_update (void *tray, const char *tooltip, int running)
{
  TgwsTray *t = tray;
  if (t == NULL)
    return;
  t->running = running;
  wchar_t *tip = to_w (tooltip);
  /* szTip is a fixed 128-wchar field. */
  t->nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  wcsncpy (t->nid.szTip, tip, G_N_ELEMENTS (t->nid.szTip) - 1);
  t->nid.szTip[G_N_ELEMENTS (t->nid.szTip) - 1] = L'\0';
  g_free (tip);
  Shell_NotifyIconW (NIM_MODIFY, &t->nid);
}

void
tgws_tray_free (void *tray)
{
  TgwsTray *t = tray;
  if (t == NULL)
    return;
  if (t->hwnd != NULL) {
    Shell_NotifyIconW (NIM_DELETE, &t->nid);
    DestroyWindow (t->hwnd);
  }
  if (t->nid.hIcon != NULL)
    DestroyIcon (t->nid.hIcon);
  g_free (t->open);
  g_free (t->open_tg);
  g_free (t->start);
  g_free (t->stop);
  g_free (t->restart);
  g_free (t->quit);
  g_free (t);
}
