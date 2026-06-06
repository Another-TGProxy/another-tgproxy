# A real libintl that replaces GLib's stub proxy-libintl on Android (which is
# built -DSTUB_ONLY and never translates). The parent project registers this via
# meson.override_dependency('intl', ...) before GLib is configured, so GLib, GTK
# and the app all link it. Shared, soversion 8 — same shape proxy-libintl ships,
# so it lands in the APK's jniLibs and resolves -lintl at runtime.
project('realintl', 'c', version: '1')

intl_lib = library('intl', 'libintl.c',
  soversion: 8,
  install: true)

intl_dep = declare_dependency(
  link_with: intl_lib,
  include_directories: include_directories('.'))
