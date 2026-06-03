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

mtproxy_dep = dependency('mtproxy-ws')   # the core: libmtproxyws + headers
deps = [
  dependency('glib-2.0'),
  dependency('gio-2.0'),
  dependency('gio-unix-2.0'),
  dependency('gtk4'),
  dependency('libadwaita-1', version: '>= 1.7'),   # Adw.WrapBox, Adw.ToggleGroup
  dependency('json-glib-1.0'),
  mtproxy_dep,
]

# The core ships its Vala binding (mtproxy-ws.vapi) in its own datadir; add it
# to valac's search path so this builds against a non-system install too.
vala_extra = ['--pkg', 'mtproxy-ws', '--pkg', 'posix']
mtproxy_vapidir = mtproxy_dep.get_variable(pkgconfig: 'vapidir', default_value: '')
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
  'src/platform.vala',
  'src/ui/window.vala',
  'src/ui/home-view.vala',
  'src/ui/settings-view.vala',
  'src/ui/log-view.vala',
  'src/daemon/daemon.vala',
  'src/daemon/control.vala',
  'src/daemon/tray.vala',
  'src/controller/client.vala',
  'src/controller/service.vala',
)

executable('another-tgproxy',
  sources, config_h, resources,
  dependencies: deps,
  vala_args: vala_extra,
  c_args: ['-DGETTEXT_PACKAGE="@0@"'.format(meson.project_name())],
  include_directories: include_directories('.'),
  install: true,
)

subdir('po')
subdir('data')

gnome.post_install(
  gtk_update_icon_cache: true,
  update_desktop_database: true,
)
