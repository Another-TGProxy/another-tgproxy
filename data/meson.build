base = 'space.ampernic.AnotherTGProxy'
po_dir = meson.project_source_root() / 'po'

# Desktop entry, AppStream metainfo and D-Bus activation are Linux/desktop
# integration; Windows ships a self-contained zip with none of these (and its
# msgfmt lacks the AppStream ITS rules), so skip them there.
if host_machine.system() != 'windows'

# Desktop entry: @-substitute, then merge translations from po/.
desktop_conf = configuration_data()
desktop_conf.set('APP_ID', app_id_relevant)
desktop_conf.set('APP_NAME', app_name)
desktop_conf.set('BINARY', meson.project_name())

desktop_in = configure_file(
  input: base + '.desktop.in.in',
  output: app_id_relevant + '.desktop.in',
  configuration: desktop_conf,
)
desktop_file = i18n.merge_file(
  input: desktop_in,
  output: app_id_relevant + '.desktop',
  type: 'desktop',
  po_dir: po_dir,
  install: true,
  install_dir: get_option('datadir') / 'applications',
)

desktop_validate = find_program('desktop-file-validate', required: false)
if desktop_validate.found()
  test('validate-desktop', desktop_validate, args: [desktop_file])
endif

# AppStream metainfo.
metainfo_conf = configuration_data()
metainfo_conf.set('APP_ID', app_id_relevant)

metainfo_in = configure_file(
  input: base + '.metainfo.xml.in.in',
  output: app_id_relevant + '.metainfo.xml.in',
  configuration: metainfo_conf,
)
metainfo_file = i18n.merge_file(
  input: metainfo_in,
  output: app_id_relevant + '.metainfo.xml',
  type: 'xml',
  po_dir: po_dir,
  install: true,
  install_dir: get_option('datadir') / 'metainfo',
)

appstreamcli = find_program('appstreamcli', required: false)
if appstreamcli.found()
  test('validate-metainfo', appstreamcli,
    args: ['validate', '--no-net', metainfo_file])
endif

# D-Bus activation services. The daemon one lets the quick-settings extension
# start it on demand; the GUI one (DBusActivatable) lets the daemon raise the
# window through the session bus, so it works even from a headless context.
svc_conf = configuration_data()
svc_conf.set('APP_ID', app_id_relevant)
svc_conf.set('DAEMON_ID', app_id_relevant + '.Daemon')
svc_conf.set('bindir', get_option('prefix') / get_option('bindir'))
configure_file(
  input: base + '.Daemon.service.in',
  output: app_id_relevant + '.Daemon.service',
  configuration: svc_conf,
  install: true,
  install_dir: get_option('datadir') / 'dbus-1' / 'services',
)
configure_file(
  input: base + '.service.in',
  output: app_id_relevant + '.service',
  configuration: svc_conf,
  install: true,
  install_dir: get_option('datadir') / 'dbus-1' / 'services',
)

endif  # not windows

# Icons renamed to the profile-relevant app-id so a Devel build resolves its own.
# The development profile ships its striped Devel variant (scalable only).
scalable_icon = is_devel ? base + '.Devel.svg' : base + '.svg'
install_data(
  'icons/hicolor/scalable/apps' / scalable_icon,
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps',
  rename: app_id_relevant + '.svg',
)
if not is_devel
  foreach sz : ['64', '128', '256']
    install_data(
      'icons/hicolor' / (sz + 'x' + sz) / 'apps' / (base + '.png'),
      install_dir: get_option('datadir') / 'icons' / 'hicolor' / (sz + 'x' + sz) / 'apps',
      rename: app_id_relevant + '.png',
    )
  endforeach
endif

# The symbolic icon for the Quick Settings toggle (libqshub -> hub). The now-removed
# GNOME Shell extension used to ship it; the app installs it itself now, renamed to
# the app-id so stable and Devel coexist (QshubController loads it by that name).
install_data(
  'icons/hicolor/scalable/actions/another-tgproxy-symbolic.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'actions',
  rename: app_id_relevant + '-symbolic.svg',
)
