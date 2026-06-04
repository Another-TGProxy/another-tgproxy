/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef MAC_TRAY_H
#define MAC_TRAY_H

/* Minimal NSStatusItem menu-bar tray for macOS. Lives in the GUI process, which
 * (via GTK's quartz backend) pumps the AppKit run loop. Labels are passed in from
 * Vala (already gettext-translated); icon_path is an optional template PNG. */

/* action: 0 open, 1 open-telegram, 2 toggle, 3 restart, 4 quit */
typedef void (*MacTrayCb) (int action, void *user_data);

void *mac_tray_new (MacTrayCb cb, void *user_data, const char *icon_path,
                    const char *l_open, const char *l_open_telegram,
                    const char *l_start, const char *l_stop,
                    const char *l_restart, const char *l_quit);
void  mac_tray_update (void *tray, const char *tooltip, int running);
void  mac_tray_free (void *tray);

#endif
