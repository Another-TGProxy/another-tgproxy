# A real libintl that takes the place of GLib's stub proxy-libintl on Android
# (frida's, built -DSTUB_ONLY, never translates). We deliberately claim the
# subproject name "proxy-libintl": the parent configures it first, so GLib's
# `dependency('intl')` (via override) AND GTK's `dependency('', fallback:
# ['proxy-libintl', 'intl_dep'])` both resolve to this instead of fetching the
# stub. Shared, soversion 8 — same shape, so it lands in the APK jniLibs.
project('proxy-libintl', 'c', version: '1')

intl_lib = library('intl', 'libintl.c',
  soversion: 8,
  install: true)

intl_dep = declare_dependency(
  link_with: intl_lib,
  include_directories: include_directories('.'))
