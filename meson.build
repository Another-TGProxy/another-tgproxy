# another-tgproxy GUI — GTK4/libadwaita front-end + background daemon for the
# mtproxy-ws engine. Build-depends on the installed `mtproxy-ws` package
# (pkg-config + the bundled vala binding); build/install core first.
project('another-tgproxy', ['c', 'vala'],
  version: '2.0.0',
  meson_version: '>= 0.62',
  default_options: ['warning_level=2'],
  license: 'GPL-3.0-or-later',
)

gnome = import('gnome')
i18n = import('i18n')

app_id = 'space.ampernic.AnotherTGProxy'
app_id_relevant = app_id
app_name = 'Another TGProxy'
app_dirname = 'AnotherTGProxy'
homepage = 'https://github.com/Another-TGProxy'
bugtracker = 'https://github.com/Another-TGProxy/another-tgproxy/issues'
is_devel = false
# Installed builds read translations from the prefix; an uninstalled dev build
# reads them straight from the build tree, where i18n.gettext writes the .mo.
localedir = get_option('prefix') / get_option('localedir')

if get_option('profile') == 'development'
  is_devel = true
  app_id_relevant = app_id + '.Devel'
  app_name = app_name + ' (Devel)'
  app_dirname = app_dirname + '.Devel'
  localedir = meson.project_build_root() / 'po'
endif

conf = configuration_data()
conf.set_quoted('APP_ID', app_id)
conf.set_quoted('APP_ID_RELEVANT', app_id_relevant)
conf.set_quoted('DAEMON_ID', app_id_relevant + '.Daemon')
conf.set_quoted('APP_NAME', app_name)
conf.set_quoted('APP_DIRNAME', app_dirname)
conf.set_quoted('VERSION', meson.project_version())
conf.set_quoted('OS', host_machine.system())
conf.set_quoted('GETTEXT_PACKAGE', meson.project_name())
conf.set_quoted('LOCALEDIR', localedir)
conf.set_quoted('HOMEPAGE', homepage)
conf.set_quoted('BUGTRACKER', bugtracker)
conf.set10('IS_DEVEL', is_devel)
config_h = configure_file(output: 'build-config.h', configuration: conf)

# On Android GLib/GTK fall back to proxy-libintl built -DSTUB_ONLY, so gettext is
# a no-op and nothing (GLib, GTK or this app) translates. We ship a real libintl
# AS the "proxy-libintl" subproject and configure it first: claiming that name
# makes GTK's anonymous `dependency('', fallback: ['proxy-libintl', ...])` reuse
# ours instead of fetching the stub, while the override covers GLib's named
# `dependency('intl')`. Both must happen before GLib is configured (below).
if host_machine.system() == 'android'
  intl_subproject = subproject('proxy-libintl')
  meson.override_dependency('intl', intl_subproject.get_variable('intl_dep'))
endif

# Use the system core on desktop; on Android (no system lib) fall back to the
# mtproxy-ws meson subproject (subprojects/mtproxy-ws.wrap).
mtproxy_dep = dependency('mtproxy-ws',
  fallback: ['mtproxy-ws', 'mtproxyws_dep'])
deps = [
  dependency('glib-2.0'),
  dependency('gio-2.0'),
  dependency('gtk4'),
  dependency('libadwaita-1', version: '>= 1.7'),   # Adw.WrapBox, Adw.ToggleGroup
  dependency('json-glib-1.0'),
  mtproxy_dep,
]
# gio-unix (Unix sockets, GDesktopAppInfo) is Linux/macOS-only; Windows uses TCP
# + token IPC and has no .desktop, all behind #if WINDOWS.
if host_machine.system() != 'windows'
  deps += dependency('gio-unix-2.0')
endif

# The core ships its Vala binding (mtproxy-ws.vapi) in its own datadir; add it
# to valac's search path so this builds against a non-system install too.
vala_extra = ['--pkg', 'mtproxy-ws', '--pkg', 'posix']
if host_machine.system() == 'darwin'
  # GDesktopAppInfo / SNI / session D-Bus are Linux-only; macOS code paths are
  # guarded with #if DARWIN in the Vala sources.
  vala_extra += ['--define=DARWIN']
elif host_machine.system() == 'windows'
  # No Unix sockets / D-Bus / glib-unix signals on Windows: control IPC is TCP
  # + token, the service is a detached process, all behind #if WINDOWS.
  vala_extra += ['--define=WINDOWS']
elif host_machine.system() == 'android'
  # Android is single-process (no daemon/D-Bus/tray); #if ANDROID code paths.
  vala_extra += ['--define=ANDROID']
  # The target gtk4/libadwaita/json-glib come from vapi-less Pixiewood/wrap
  # subprojects, so meson can't auto-add their --pkg for valac. Name them
  # explicitly; valac binds against the host vapis (generated C is cross-built
  # against the real Android headers/libs).
  vala_extra += [
    '--pkg', 'gtk4',
    '--pkg', 'libadwaita-1',
    '--pkg', 'json-glib-1.0',
    '--pkg', 'gio-2.0',
    '--pkg', 'gio-unix-2.0',
  ]
endif
mtproxy_vapidir = mtproxy_dep.get_variable('vapidir', default_value: '')
if mtproxy_vapidir != ''
  vala_extra += ['--vapidir', mtproxy_vapidir]
endif

blueprint_compiler = find_program('blueprint-compiler')
ui_targets = []
foreach view : ['window', 'home-view', 'settings-view', 'log-view']
  ui_targets += custom_target(view + '.ui',
    input: 'data/ui' / (view + '.blp'),
    output: view + '.ui',
    command: [blueprint_compiler, 'compile', '--output', '@OUTPUT@', '@INPUT@'],
  )
endforeach
resources = gnome.compile_resources('another-tgproxy-resources',
  'data/gresource.xml',
  source_dir: [meson.current_build_dir(), meson.current_source_dir() / 'data'],
  dependencies: ui_targets,
  c_name: 'tgws',
)

sources = files(
  'src/build-config.vapi',
  'src/main.vala',
  'src/application.vala',
  'src/config.vala',
  'src/ipc.vala',
  'src/logging.vala',
  'src/platform.vala',
  'src/ui/window.vala',
  'src/ui/home-view.vala',
  'src/ui/settings-view.vala',
  'src/ui/log-view.vala',
  'src/controller/client.vala',
  'src/controller/service.vala',
  'src/android/engine_host.vala',   # #if ANDROID — empty elsewhere
)
if host_machine.system() != 'android'
  # The separate daemon + its D-Bus/SNI presenters are desktop-only.
  sources += files(
    'src/daemon/daemon.vala',
    'src/daemon/control.vala',
    'src/daemon/tray.vala',
  )
endif

# Platform-specific extras (macOS menu-bar tray via NSStatusItem; Android JNI glue).
mac_sources = []
android_sources = []
win_sources = []
extra_deps = []
extra_link_args = []
inc_dirs = ['.']
if host_machine.system() == 'darwin'
  add_languages('objc', native: false)
  mac_sources = files('src/mac/mac_tray.m', 'src/mac/mac_tray.vapi')
  extra_deps += dependency('appleframeworks', modules: ['Cocoa'])
  inc_dirs += 'src/mac'
elif host_machine.system() == 'windows'
  # Win32 glue (running-exe path, PID; the Shell_NotifyIcon tray lands here too).
  win_sources = files('src/win/win_compat.c', 'src/win/win_compat.vapi')
  inc_dirs += 'src/win'
elif host_machine.system() == 'android'
  # C glue over the gdk-android public API (battery-optimization exemption, …).
  android_sources = files('src/android/android_bridge.c', 'src/android/android_bridge.vapi')
  inc_dirs += 'src/android'
endif

# android_exe_type is a Pixiewood meson-fork kwarg; only pass it when targeting
# Android so plain meson doesn't choke on an unknown kwarg.
exe_kwargs = {}
if host_machine.system() == 'android'
  exe_kwargs = {'android_exe_type': 'application'}
elif host_machine.system() == 'windows'
  # GUI subsystem: neither the app nor the spawned --daemon flashes a console.
  exe_kwargs = {'win_subsystem': 'windows'}
endif

executable('another-tgproxy',
  sources, mac_sources, android_sources, win_sources, config_h, resources,
  dependencies: deps + extra_deps,
  vala_args: vala_extra,
  c_args: ['-DGETTEXT_PACKAGE="@0@"'.format(meson.project_name())],
  link_args: extra_link_args,
  include_directories: include_directories(inc_dirs),
  kwargs: exe_kwargs,
  install: true,
)

subdir('po')
subdir('data')

# Desktop-install hooks (icon cache / desktop database). Skipped on the Android
# cross build: they'd run cross-built host tools (gtk4-update-icon-cache) that
# need an exe_wrapper, and an APK has no such caches anyway.
if host_machine.system() == 'linux'
  gnome.post_install(
    gtk_update_icon_cache: true,
    update_desktop_database: true,
  )
endif
