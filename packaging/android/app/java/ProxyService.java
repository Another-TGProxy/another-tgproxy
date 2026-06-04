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

// An ongoing foreground service whose only job is to hold the process at
// foreground priority while the in-process proxy runs. It does no work itself —
// the engine lives on its own threads in the same process.
public class ProxyService extends Service {
	private static final String CHANNEL = "proxy";
	private static final int NOTIFICATION_ID = 1;

	@Override
	public void onCreate() {
		super.onCreate();

		NotificationManager nm = getSystemService(NotificationManager.class);
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
			NotificationChannel ch = new NotificationChannel(
					CHANNEL, "Proxy", NotificationManager.IMPORTANCE_LOW);
			ch.setShowBadge(false);
			nm.createNotificationChannel(ch);
		}

		Intent launch = getPackageManager().getLaunchIntentForPackage(getPackageName());
		PendingIntent pi = launch == null ? null : PendingIntent.getActivity(
				this, 0, launch,
				PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);

		Notification.Builder b = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
				? new Notification.Builder(this, CHANNEL)
				: new Notification.Builder(this);
		Notification n = b
				.setContentTitle("Another TGProxy")
				.setContentText("Proxy running in the background")
				// A simple monochrome vector (the adaptive-icon foreground) — a
				// full colour/adaptive icon is not a valid notification small icon.
				.setSmallIcon(R.drawable.ic_launcher_foreground)
				.setContentIntent(pi)
				.setOngoing(true)
				.build();

		try {
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
				startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
			else
				startForeground(NOTIFICATION_ID, n);
		} catch (Exception e) {
			// Don't take the process down if promotion is refused; fall back to a
			// plain service rather than crashing the whole app.
			stopSelf();
		}
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

	// Swiping the app away from recents tears down the process; don't keep a
	// zombie proxy running with no way to control it.
	@Override
	public void onTaskRemoved(Intent rootIntent) {
		stopSelf();
	}
}
