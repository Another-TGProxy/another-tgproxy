/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "android_bridge.h"

#include <jni.h>
#include <gdk/android/gdkandroid.h>

/* Resolve the JNI environment and the current Activity (which is a Context) from
 * a realized toplevel surface. Returns FALSE if the surface isn't an Android
 * toplevel yet. */
static gboolean
resolve (GdkSurface *surface, JNIEnv **env, jobject *activity, GdkAndroidToplevel **toplevel)
{
  if (surface == NULL || !GDK_IS_ANDROID_TOPLEVEL (surface))
    {
      g_warning ("android bridge: surface is not an Android toplevel yet");
      return FALSE;
    }
  GdkDisplay *display = gdk_surface_get_display (surface);
  *env = gdk_android_display_get_env (display);
  if (*env == NULL)
    {
      g_warning ("android bridge: no JNI env from display");
      return FALSE;
    }
  *toplevel = GDK_ANDROID_TOPLEVEL (surface);
  *activity = gdk_android_toplevel_get_activity (*toplevel);
  if (*activity == NULL)
    g_warning ("android bridge: toplevel has no activity");
  return *activity != NULL;
}

static jstring
package_name (JNIEnv *env, jobject activity)
{
  jclass ctx = (*env)->GetObjectClass (env, activity);
  jmethodID m = (*env)->GetMethodID (env, ctx, "getPackageName", "()Ljava/lang/String;");
  jstring pkg = (*env)->CallObjectMethod (env, activity, m);
  (*env)->DeleteLocalRef (env, ctx);
  return pkg;
}

gboolean
tgws_android_is_ignoring_battery_optimizations (GdkSurface *surface)
{
  JNIEnv *env;
  jobject activity;
  GdkAndroidToplevel *toplevel;
  if (!resolve (surface, &env, &activity, &toplevel))
    return FALSE; /* couldn't check -> let the UI prompt rather than skip */

  jclass ctx = (*env)->GetObjectClass (env, activity);
  jmethodID get_service = (*env)->GetMethodID (env, ctx, "getSystemService",
                                               "(Ljava/lang/String;)Ljava/lang/Object;");
  jstring power = (*env)->NewStringUTF (env, "power");
  jobject pm = (*env)->CallObjectMethod (env, activity, get_service, power);
  (*env)->DeleteLocalRef (env, power);
  (*env)->DeleteLocalRef (env, ctx);
  if (pm == NULL)
    return TRUE;

  jstring pkg = package_name (env, activity);
  jclass pm_cls = (*env)->GetObjectClass (env, pm);
  jmethodID is_ign = (*env)->GetMethodID (env, pm_cls, "isIgnoringBatteryOptimizations",
                                          "(Ljava/lang/String;)Z");
  jboolean r = (*env)->CallBooleanMethod (env, pm, is_ign, pkg);
  (*env)->DeleteLocalRef (env, pm_cls);
  (*env)->DeleteLocalRef (env, pm);
  (*env)->DeleteLocalRef (env, pkg);
  return r ? TRUE : FALSE;
}

void
tgws_android_request_ignore_battery_optimizations (GdkSurface *surface)
{
  JNIEnv *env;
  jobject activity;
  GdkAndroidToplevel *toplevel;
  if (!resolve (surface, &env, &activity, &toplevel))
    return;

  /* Uri uri = Uri.parse("package:" + getPackageName()) */
  jstring pkg = package_name (env, activity);
  const char *cpkg = (*env)->GetStringUTFChars (env, pkg, NULL);
  char *uri_str = g_strconcat ("package:", cpkg, NULL);
  (*env)->ReleaseStringUTFChars (env, pkg, cpkg);
  (*env)->DeleteLocalRef (env, pkg);

  jclass uri_cls = (*env)->FindClass (env, "android/net/Uri");
  jmethodID parse = (*env)->GetStaticMethodID (env, uri_cls, "parse",
                                               "(Ljava/lang/String;)Landroid/net/Uri;");
  jstring juri = (*env)->NewStringUTF (env, uri_str);
  g_free (uri_str);
  jobject uri = (*env)->CallStaticObjectMethod (env, uri_cls, parse, juri);
  (*env)->DeleteLocalRef (env, juri);

  /* Intent intent = new Intent(ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, uri) */
  jclass intent_cls = (*env)->FindClass (env, "android/content/Intent");
  jmethodID ctor = (*env)->GetMethodID (env, intent_cls, "<init>",
                                        "(Ljava/lang/String;Landroid/net/Uri;)V");
  jstring action = (*env)->NewStringUTF (env,
      "android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS");
  jobject intent = (*env)->NewObject (env, intent_cls, ctor, action, uri);

  GError *error = NULL;
  gdk_android_toplevel_launch_activity (toplevel, intent, &error);
  if (error != NULL)
    {
      g_warning ("battery-optimization settings launch failed: %s", error->message);
      g_clear_error (&error);
    }

  (*env)->DeleteLocalRef (env, action);
  (*env)->DeleteLocalRef (env, intent);
  (*env)->DeleteLocalRef (env, uri);
  (*env)->DeleteLocalRef (env, uri_cls);
  (*env)->DeleteLocalRef (env, intent_cls);
}
