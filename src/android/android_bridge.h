/* SPDX-License-Identifier: GPL-3.0-or-later */
#pragma once
#include <glib.h>
#include <gdk/gdk.h>

G_BEGIN_DECLS

/* Android-only glue, built against the gdk-android public API. The GTK/Vala UI
 * calls these to talk to the platform (battery-optimization exemption, etc.);
 * everything goes through gdk_android_display_get_env() +
 * gdk_android_toplevel_get_activity()/launch_activity(), no private symbols. */

gboolean tgws_android_is_ignoring_battery_optimizations (GdkSurface *surface);
void     tgws_android_request_ignore_battery_optimizations (GdkSurface *surface);

/* Cache the ProxyService class via the activity's (app) class loader. Must be
 * called once with a realized surface before set_notification_text works: a
 * native thread's FindClass uses the system loader, which can't see app classes. */
void tgws_android_bind_notification (GdkSurface *surface);

/* Update the ongoing foreground-service notification's text (live stats). Uses
 * the class cached by bind_notification, so it needs no surface. */
void tgws_android_set_notification_text (const char *text);

/* Open this app's system notification settings. */
void tgws_android_open_notification_settings (GdkSurface *surface);

G_END_DECLS
