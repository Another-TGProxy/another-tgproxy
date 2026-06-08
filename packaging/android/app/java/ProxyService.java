// SPDX-License-Identifier: GPL-3.0-or-later
package space.ampernic.anothertgproxy;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;

// An ongoing foreground service that holds the process at foreground priority
// while the in-process proxy runs (the engine lives on its own threads in the
// same process). Its notification doubles as the Android status display, updated
// live from the engine via ProxyService.setText() (called through the JNI bridge).
public class ProxyService extends Service {
	private static final String CHANNEL = "proxy";
	private static final int NOTIFICATION_ID = 1;

	private static volatile ProxyService instance;

	private String text = "Proxy running in the background";

	@Override
	public void onCreate() {
		super.onCreate();
		instance = this;

		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
			NotificationChannel ch = new NotificationChannel(
					CHANNEL, "Proxy", NotificationManager.IMPORTANCE_LOW);
			ch.setShowBadge(false);
			getSystemService(NotificationManager.class).createNotificationChannel(ch);
		}

		try {
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
				startForeground(NOTIFICATION_ID, build(), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
			else
				startForeground(NOTIFICATION_ID, build());
		} catch (Exception e) {
			stopSelf();
		}
	}

	private Notification build() {
		Intent launch = getPackageManager().getLaunchIntentForPackage(getPackageName());
		PendingIntent pi = launch == null ? null : PendingIntent.getActivity(
				this, 0, launch,
				PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);

		Notification.Builder b = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
				? new Notification.Builder(this, CHANNEL)
				: new Notification.Builder(this);
		return b
				.setContentTitle("Another TGProxy")
				.setContentText(text)
				// A simple monochrome vector (the adaptive-icon foreground) — a
				// full colour/adaptive icon is not a valid notification small icon.
				.setSmallIcon(R.drawable.ic_launcher_foreground)
				.setContentIntent(pi)
				.setOngoing(true)
				.build();
	}

	private void update() {
		getSystemService(NotificationManager.class).notify(NOTIFICATION_ID, build());
	}

	// Called from the engine (via the JNI bridge) to show live stats.
	public static void setText(String s) {
		ProxyService i = instance;
		if (i == null || s == null)
			return;
		i.text = s;
		i.update();
	}

	@Override
	public int onStartCommand(Intent intent, int flags, int startId) {
		return START_STICKY;
	}

	@Override
	public IBinder onBind(Intent intent) {
		return null;
	}

	// specialUse has no enforced time limit, but honour a timeout if one ever
	// fires rather than risking an ANR.
	@Override
	public void onTimeout(int startId) {
		stopSelf();
	}

	@Override
	public void onDestroy() {
		if (instance == this)
			instance = null;
		super.onDestroy();
	}

	// Swiping the app away from recents tears down the process; don't keep a
	// zombie proxy running with no way to control it.
	@Override
	public void onTaskRemoved(Intent rootIntent) {
		stopSelf();
	}
}
