// SPDX-License-Identifier: GPL-3.0-or-later
package space.ampernic.anothertgproxy;

import android.content.Intent;
import android.os.Build;

import org.gtk.android.RuntimeApplication;

// Replaces org.gtk.android.RuntimeApplication as the manifest <application> so we
// can start a foreground service when the app launches. The proxy engine runs on
// its own threads inside this same process; the foreground service keeps the
// process at foreground priority so Android does not kill it (and the proxy) when
// the window is backgrounded.
public class ProxyApplication extends RuntimeApplication {
	@Override
	public void onCreate() {
		super.onCreate();
		Intent svc = new Intent(this, ProxyService.class);
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
			startForegroundService(svc);
		else
			startService(svc);
	}
}
