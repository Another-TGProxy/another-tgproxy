// SPDX-License-Identifier: GPL-3.0-or-later
package space.ampernic.anothertgproxy;

import android.app.Activity;
import android.app.Application;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageInstaller;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;

import java.io.FileInputStream;
import java.io.InputStream;
import java.io.OutputStream;
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

	// Implemented in the GTK app's native bridge (registered once a surface
	// exists). Fired on every resume so the UI can re-check things like the
	// battery-optimization exemption. Until it's registered (the very first
	// resume) it throws UnsatisfiedLinkError, which we ignore.
	private static native void nativeOnResume();

	// In-app update: stream the downloaded APK into a PackageInstaller session
	// and commit it, which raises the system install prompt. Called from native
	// (libstation station_android_install_apk) once the download lands. Avoids a
	// FileProvider (no androidx dependency) and file:// URI exposure. The app
	// still needs the REQUEST_INSTALL_PACKAGES permission for the prompt to show.
	public static void installApk(Context ctx, String path) {
		try {
			final Context app = ctx.getApplicationContext();
			final String action = app.getPackageName() + ".INSTALL_STATUS";

			// PackageInstaller doesn't pop the prompt itself: on commit the system
			// sends STATUS_PENDING_USER_ACTION to our IntentSender, carrying the
			// confirmation Intent we must startActivity() to show it.
			final BroadcastReceiver[] holder = new BroadcastReceiver[1];
			holder[0] = new BroadcastReceiver() {
				@Override public void onReceive(Context c, Intent i) {
					int status = i.getIntExtra(PackageInstaller.EXTRA_STATUS,
							PackageInstaller.STATUS_FAILURE);
					if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
						Intent confirm = i.getParcelableExtra(Intent.EXTRA_INTENT);
						if (confirm != null) {
							confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
							app.startActivity(confirm);
						}
					} else {
						try { app.unregisterReceiver(holder[0]); } catch (Exception ignored) {}
					}
				}
			};
			IntentFilter filter = new IntentFilter(action);
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
				app.registerReceiver(holder[0], filter, Context.RECEIVER_NOT_EXPORTED);
			else
				app.registerReceiver(holder[0], filter);

			PackageInstaller pi = app.getPackageManager().getPackageInstaller();
			PackageInstaller.SessionParams params = new PackageInstaller.SessionParams(
					PackageInstaller.SessionParams.MODE_FULL_INSTALL);
			int sessionId = pi.createSession(params);
			PackageInstaller.Session session = pi.openSession(sessionId);
			try (InputStream in = new FileInputStream(path);
					OutputStream out = session.openWrite("apk", 0, -1)) {
				byte[] buf = new byte[65536];
				int n;
				while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
				session.fsync(out);
			}
			Intent intent = new Intent(action).setPackage(app.getPackageName());
			int flags = PendingIntent.FLAG_UPDATE_CURRENT;
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
				flags |= PendingIntent.FLAG_MUTABLE;
			PendingIntent pending = PendingIntent.getBroadcast(app, sessionId, intent, flags);
			session.commit(pending.getIntentSender());
			session.close();
		} catch (Exception e) {
			android.util.Log.e("AnotherTGProxy", "installApk failed", e);
		}
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

		try {
			nativeOnResume();
		} catch (UnsatisfiedLinkError e) {
			// not registered yet (first resume, before the surface maps)
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
