// SPDX-License-Identifier: GPL-3.0-or-later
[CCode (cheader_filename = "android_bridge.h")]
namespace TgwsAndroid {
    [CCode (cname = "tgws_android_is_ignoring_battery_optimizations")]
    public bool is_ignoring_battery_optimizations (Gdk.Surface surface);
    [CCode (cname = "tgws_android_request_ignore_battery_optimizations")]
    public void request_ignore_battery_optimizations (Gdk.Surface surface);
}
