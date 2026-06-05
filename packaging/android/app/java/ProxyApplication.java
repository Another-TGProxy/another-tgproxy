// SPDX-License-Identifier: GPL-3.0-or-later
package space.ampernic.anothertgproxy;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.Application;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.PowerManager;
import android.provider.Settings;

import java.util.Locale;

import org.gtk.android.RuntimeApplication;

// Replaces org.gtk.android.RuntimeApplication as the manifest <application> so we
// can start the foreground service that keeps the proxy alive in the background.
//
// The service is NOT started from onCreate: at that point no activity is resumed
// yet, so the app is not "foreground" by the FGS rules and startForegroundService
// throws ForegroundServiceStartNotAllowedException (Android 12+). Instead we wait
// for the first resumed activity — then the start is allowed and the main thread
// is free, so the service promotes itself within the timeout. We also request the
// notification permission and nudge the user to exempt us from battery
// optimization (a foreground service alone doesn't survive Doze / App Standby).
public class ProxyApplication extends RuntimeApplication {
	private boolean serviceStarted = false;
	private boolean batteryPrompted = false;

	@Override
	public void onCreate() {
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

		if (!serviceStarted) {
			serviceStarted = true;
			Intent svc = new Intent(this, ProxyService.class);
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
				startForegroundService(svc);
			else
				startService(svc);
		}

		maybePromptBatteryOptimization(activity);
	}

	// A foreground service keeps the process alive against memory pressure, but
	// aggressive battery management (Doze / App Standby) still freezes it after a
	// while. Only a battery-optimization exemption prevents that, and it needs the
	// user's consent. Nudge once per launch until it's granted.
	private void maybePromptBatteryOptimization(Activity activity) {
		if (batteryPrompted)
			return;
		PowerManager pm = getSystemService(PowerManager.class);
		if (pm == null || pm.isIgnoringBatteryOptimizations(getPackageName()))
			return;
		batteryPrompted = true;

		boolean ru = Locale.getDefault().getLanguage().equals("ru");
		String title = ru ? "Работа в фоне" : "Background operation";
		String message = ru
				? "Чтобы прокси не отключался в фоне, отключите оптимизацию "
						+ "батареи для этого приложения. Иначе Android может "
						+ "останавливать его через какое-то время."
				: "To keep the proxy running in the background, disable battery "
						+ "optimization for this app. Otherwise Android may stop "
						+ "it after a while.";
		String open = ru ? "Открыть настройки" : "Open settings";
		String later = ru ? "Позже" : "Later";

		new AlertDialog.Builder(activity)
				.setTitle(title)
				.setMessage(message)
				.setCancelable(true)
				.setPositiveButton(open, (dialog, which) -> openBatterySettings(activity))
				.setNegativeButton(later, (dialog, which) -> dialog.dismiss())
				.show();
	}

	private void openBatterySettings(Activity activity) {
		// Goes straight to the per-app "allow / don't optimize" confirmation.
		try {
			Intent i = new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
					Uri.parse("package:" + getPackageName()));
			activity.startActivity(i);
		} catch (Exception e) {
			// Fall back to the general battery-optimization list if the targeted
			// action is unavailable on this ROM.
			try {
				activity.startActivity(new Intent(
						Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS));
			} catch (Exception ignored) {
			}
		}
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
