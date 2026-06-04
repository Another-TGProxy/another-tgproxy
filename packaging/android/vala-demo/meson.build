project('adwdemo', ['c', 'vala'], version: '1.0.0')

executable('adwdemo',
  'demo.vala',
  dependencies: [
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
    dependency('gtk4'),
    dependency('libadwaita-1'),
  ],
  # valac runs on the build host; point it at the host vapis (the cross GTK is
  # built with vapi=false). The C it emits is cross-compiled against the real
  # Android GTK headers/libs.
  vala_args: ['--pkg', 'gtk4', '--pkg', 'libadwaita-1'],
  android_exe_type: 'application',
  install: true,
)

install_data('space.ampernic.AdwDemo.metainfo.xml',
  install_dir: get_option('datadir') / 'metainfo')
