// SPDX-License-Identifier: GPL-3.0-or-later
package space.ampernic.anothertgproxy;

import android.app.Activity;
import android.app.Application;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;

import java.util.Locale;

import org.gtk.android.RuntimeApplication;

// Replaces org.gtk.android.RuntimeApplication as the manifest <application> so we
// can start the foreground service that keeps the proxy alive in the background.
//
// The service is NOT started from onCreate: at that point no activity is resumed
// yet, so the app is not "foreground" by the FGS rules and startForegroundService
// throws ForegroundServiceStartNotAllowedException (Android 12+). Instead we wait
// for the first resumed activity — then the start is allowed and the main thread
// is free, so the service promotes itself within the timeout. The notification
// permission is requested here too. The battery-optimization nudge lives in the
// GTK UI (Adw dialog via the gdk-android bridge), not here.
public class ProxyApplication extends RuntimeApplication {
	private boolean serviceStarted = false;

	@Override
	public void onCreate() {
		// Bionic sets no locale env, so GLib's gettext (proxy-libintl) sees "C"
		// and never translates. Export the system language into the process env
		// before super.onCreate() starts the native runtime, so getenv("LANGUAGE")
		// resolves on the GTK side.
		String lang = Locale.getDefault().getLanguage();
		if (lang != null && !lang.isEmpty()) {
			try {
				android.system.Os.setenv("LANGUAGE", lang, true);
			} catch (Exception e) {
				// non-fatal: app stays in English
			}
		}

		super.onCreate();
		registerActivityLifecycleCallbacks(new LifecycleHook());
	}

	private void onForeground(Activity activity) {
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
				&& checkSelfPermission("android.permission.POST_NOTIFICATIONS")
						!= PackageManager.PERMISSION_GRANTED) {
			activity.requestPermissions(
					new String[] {"android.permission.POST_NOTIFICATIONS"}, 1001);
		}

		if (serviceStarted)
			return;
		serviceStarted = true;
		Intent svc = new Intent(this, ProxyService.class);
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
			startForegroundService(svc);
		else
			startService(svc);
	}

	private final class LifecycleHook implements Application.ActivityLifecycleCallbacks {
		@Override public void onActivityResumed(Activity activity) { onForeground(activity); }
		@Override public void onActivityCreated(Activity activity, Bundle state) { }
		@Override public void onActivityStarted(Activity activity) { }
		@Override public void onActivityPaused(Activity activity) { }
		@Override public void onActivityStopped(Activity activity) { }
		@Override public void onActivitySaveInstanceState(Activity activity, Bundle out) { }
		@Override public void onActivityDestroyed(Activity activity) { }
	}
}
