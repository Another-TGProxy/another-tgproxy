project('adwdemo', 'c', version: '1.0.0')

executable('adwdemo',
  'main.c',
  dependencies: [
    dependency('gtk4'),
    dependency('libadwaita-1'),
  ],
  # Recognised only by the Pixiewood meson fork; tells it to wrap this target
  # into an Android application instead of a plain executable.
  android_exe_type: 'application',
  install: true,
)

install_data('space.ampernic.AdwDemo.metainfo.xml',
  install_dir: get_option('datadir') / 'metainfo')
