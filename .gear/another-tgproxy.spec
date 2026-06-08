%define app_id space.ampernic.AnotherTGProxy

Name:           another-tgproxy
Version:        2.0.0
Release:        alt1

Summary:        GTK4 controller for the mtproxy-ws Telegram proxy
License:        GPL-3.0-or-later
Group:          Networking/Instant messaging
URL:            https://github.com/Another-TGProxy/another-tgproxy

Vcs:            https://github.com/Another-TGProxy/another-tgproxy.git

Source0:        %name-%version.tar

# The bundled systemd service of mtproxy-ws-cli would claim the same proxy port
# as this app's own daemon; only one provider of the proxy at a time.
Conflicts:      mtproxy-ws-cli

BuildRequires(pre): rpm-macros-meson
BuildRequires: meson
BuildRequires: gcc
BuildRequires: vala
BuildRequires: blueprint-compiler
BuildRequires: gettext-tools
BuildRequires: libmtproxyws-devel
BuildRequires: libstation-devel
BuildRequires: pkgconfig(libadwaita-1) >= 1.7
BuildRequires: pkgconfig(json-glib-1.0)
%if_enabled check
BuildRequires: appstream
BuildRequires: desktop-file-utils
%endif

%description
Another TGProxy is a GTK4/libadwaita front-end and background daemon for the
mtproxy-ws engine: it runs a Telegram MTProto-over-WebSocket proxy, shows live
status and connection statistics, manages the daemon's lifecycle and produces a
shareable tg:// link. The proxy engine itself comes from libmtproxyws.

%prep
%setup

%build
%meson -Drelease_version=%version
%meson_build

%install
%meson_install
%find_lang another-tgproxy

%check
%meson_test

%files -f another-tgproxy.lang
%doc README.md README.en.md LICENSE
%_bindir/another-tgproxy
%_datadir/applications/%app_id.desktop
%_datadir/metainfo/%app_id.metainfo.xml
%_datadir/dbus-1/services/%app_id.service
%_datadir/dbus-1/services/%app_id.Daemon.service
%_datadir/icons/hicolor/scalable/apps/%app_id.svg
%_datadir/icons/hicolor/*/apps/%app_id.png

%changelog
* Sun Jun 08 2026 Anton Politov <ampernic@altlinux.org> 2.0.0-alt1
- Initial build for ALT.
