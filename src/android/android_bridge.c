/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "android_bridge.h"

#include <jni.h>
#include <gdk/android/gdkandroid.h>

/* ProxyService class, loaded via the app class loader (see bind_notification). */
static jclass g_service_cls = NULL;

/* Resume handler set by the UI; invoked on the GTK main thread on each resume. */
static TgwsAndroidResumeFunc g_resume_cb = NULL;

static gboolean
resume_on_main (gpointer data)
{
  (void) data;
  if (g_resume_cb != NULL)
    g_resume_cb ();
  return G_SOURCE_REMOVE;
}

/* JNI: ProxyApplication.nativeOnResume(). Runs on the Android UI thread, so it
 * just hands off to the GTK main loop. */
static void
native_on_resume (JNIEnv *env, jclass cls)
{
  (void) env;
  (void) cls;
  g_idle_add (resume_on_main, NULL);
}

void
tgws_android_set_resume_handler (TgwsAndroidResumeFunc cb)
{
  g_resume_cb = cb;
}

/* Load an app class through the activity's class loader (the system loader a
 * native thread would use can't see app classes). Returns a global ref or NULL. */
static jclass
load_app_class (JNIEnv *env, jobject activity, const char *dotted_name)
{
  jclass acls = (*env)->GetObjectClass (env, activity);
  jmethodID get_cl = (*env)->GetMethodID (env, acls, "getClassLoader",
                                          "()Ljava/lang/ClassLoader;");
  jobject cl = (*env)->CallObjectMethod (env, activity, get_cl);
  (*env)->DeleteLocalRef (env, acls);
  if (cl == NULL)
    return NULL;
  jclass cl_cls = (*env)->GetObjectClass (env, cl);
  jmethodID load = (*env)->GetMethodID (env, cl_cls, "loadClass",
                                        "(Ljava/lang/String;)Ljava/lang/Class;");
  (*env)->DeleteLocalRef (env, cl_cls);
  jstring name = (*env)->NewStringUTF (env, dotted_name);
  jobject cls = (*env)->CallObjectMethod (env, cl, load, name);
  (*env)->DeleteLocalRef (env, name);
  (*env)->DeleteLocalRef (env, cl);
  if ((*env)->ExceptionCheck (env))
    {
      (*env)->ExceptionClear (env);
      return NULL;
    }
  if (cls == NULL)
    return NULL;
  jclass global = (*env)->NewGlobalRef (env, cls);
  (*env)->DeleteLocalRef (env, cls);
  return global;
}

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

void
tgws_android_bind_notification (GdkSurface *surface)
{
  if (g_service_cls != NULL)
    return;
  JNIEnv *env;
  jobject activity;
  GdkAndroidToplevel *toplevel;
  if (!resolve (surface, &env, &activity, &toplevel))
    return;

  g_service_cls = load_app_class (env, activity, "space.ampernic.anothertgproxy.ProxyService");
  if (g_service_cls == NULL)
    g_warning ("android bridge: could not load ProxyService class");

  /* Bind ProxyApplication.nativeOnResume → native_on_resume. The lib is opened
   * with dlopen, so the JVM can't resolve native methods by name; register it. */
  jclass app_cls = load_app_class (env, activity, "space.ampernic.anothertgproxy.ProxyApplication");
  if (app_cls != NULL)
    {
      JNINativeMethod m = { "nativeOnResume", "()V", (void *) native_on_resume };
      if ((*env)->RegisterNatives (env, app_cls, &m, 1) != 0)
        {
          (*env)->ExceptionClear (env);
          g_warning ("android bridge: could not register nativeOnResume");
        }
      (*env)->DeleteGlobalRef (env, app_cls);
    }
}

void
tgws_android_set_notification_text (const char *text)
{
  if (g_service_cls == NULL)
    return; /* bind_notification not run yet */

  /* env from the default display: valid on the GTK main thread, where the engine
   * poll runs. ProxyService.setText updates the live foreground notification. */
  GdkDisplay *display = gdk_display_get_default ();
  if (display == NULL)
    return;
  JNIEnv *env = gdk_android_display_get_env (display);
  if (env == NULL)
    return;

  jmethodID m = (*env)->GetStaticMethodID (env, g_service_cls, "setText",
                                           "(Ljava/lang/String;)V");
  if (m != NULL)
    {
      jstring s = (*env)->NewStringUTF (env, text != NULL ? text : "");
      (*env)->CallStaticVoidMethod (env, g_service_cls, m, s);
      (*env)->DeleteLocalRef (env, s);
    }
}

void
tgws_android_open_notification_settings (GdkSurface *surface)
{
  JNIEnv *env;
  jobject activity;
  GdkAndroidToplevel *toplevel;
  if (!resolve (surface, &env, &activity, &toplevel))
    return;

  jstring pkg = package_name (env, activity);
  jclass intent_cls = (*env)->FindClass (env, "android/content/Intent");
  jmethodID ctor = (*env)->GetMethodID (env, intent_cls, "<init>", "(Ljava/lang/String;)V");
  jstring action = (*env)->NewStringUTF (env, "android.settings.APP_NOTIFICATION_SETTINGS");
  jobject intent = (*env)->NewObject (env, intent_cls, ctor, action);

  /* intent.putExtra("android.provider.extra.APP_PACKAGE", getPackageName()) */
  jmethodID put = (*env)->GetMethodID (env, intent_cls, "putExtra",
      "(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;");
  jstring key = (*env)->NewStringUTF (env, "android.provider.extra.APP_PACKAGE");
  jobject ret = (*env)->CallObjectMethod (env, intent, put, key, pkg);
  if (ret != NULL)
    (*env)->DeleteLocalRef (env, ret);

  GError *error = NULL;
  gdk_android_toplevel_launch_activity (toplevel, intent, &error);
  if (error != NULL)
    {
      g_warning ("notification settings launch failed: %s", error->message);
      g_clear_error (&error);
    }

  (*env)->DeleteLocalRef (env, key);
  (*env)->DeleteLocalRef (env, action);
  (*env)->DeleteLocalRef (env, intent);
  (*env)->DeleteLocalRef (env, intent_cls);
  (*env)->DeleteLocalRef (env, pkg);
}
