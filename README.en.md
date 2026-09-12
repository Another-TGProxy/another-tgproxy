<div align="center">

<img src="data/icons/hicolor/scalable/apps/space.ampernic.AnotherTGProxy.svg" width="128" alt="Another TGProxy logo"/>

# Another TGProxy

**A GTK4 / libadwaita front-end & background daemon for the `mtproxy-ws` engine.**

[![License](https://img.shields.io/badge/license-GPL--3.0--or--later-1C71D8.svg)](LICENSE)
![Toolkit](https://img.shields.io/badge/GTK4-libadwaita-37c871.svg)
![Language](https://img.shields.io/badge/Vala-7239b3.svg)
![Platforms](https://img.shields.io/badge/Linux_Windows_macOS_Android-lightgrey.svg)

[Русский](README.md) · **English**

</div>

---

A native app (desktop & Android) for the
**[mtproxy-ws](https://github.com/Another-TGProxy/mtproxy-ws)** Telegram
MTProto↔WebSocket proxy. On the desktop it runs the proxy as a headless background
daemon and gives you a window to control it: live status (connections, traffic),
the `tg://proxy` link, settings and a log view.

<div align="center">

<img src="data/screenshots/home.png" width="49%" alt="Home"/>
<img src="data/screenshots/settings.png" width="49%" alt="Settings"/>

</div>

## 🖥️ Status display modes

The proxy runs as a **background daemon** independent of the window — closing the
window doesn't stop it. Where its live status is shown is chosen in Settings: the
app detects the OS/desktop/delivery at runtime and offers only the modes that work
here (default — the best one: tray → background → window).

| Mode | What it is | Where |
|---|---|---|
| **Window** | Status in the app window | everywhere (fallback) |
| **Tray** | System-tray icon (SNI): menu, status header, tooltip | KDE/XFCE/…, GNOME with AppIndicator; natively Windows/macOS |
| **Background** | GNOME *Background Apps* with a configurable status line | Linux + GNOME + Flatpak |
| **Quick Settings** | A Quick Settings toggle via the [GNOME Shell extension](https://github.com/Another-TGProxy/another-tgproxy-extension) | Linux + GNOME + the extension |

## 🔨 Build

Build & install the `mtproxy-ws` core first, then the GUI on top of it:

```sh
meson setup ../core/build ../core && sudo ninja -C ../core/build install
meson setup build && ninja -C build && ./build/tg-ws-proxy
```

Dependencies: `gtk4`, `libadwaita-1` (≥ 1.7), `glib-2.0`/`gio-2.0`/`gio-unix-2.0`,
`json-glib-1.0`, `vala`, `meson`, `ninja`, `blueprint-compiler`. The
`-Dprofile=development` option gives an isolated dev build (`.Devel` app-id).
Cross-platform integration (tray, control IPC, shell helpers, Android background)
comes from **[libstation](https://github.com/Ampernic/libstation)**, pulled in as a
subproject.

## 📦 Flatpak

From the [flatpak.ampernic.space](https://flatpak.ampernic.space) repository:

```sh
flatpak remote-add --if-not-exists --user \
    ampernic https://flatpak.ampernic.space/ampernic.flatpakrepo
flatpak install --user ampernic space.ampernic.AnotherTGProxy
flatpak run space.ampernic.AnotherTGProxy
```

Under Flatpak the daemon starts as its own instance (D-Bus activation), survives
the window closing and shows up in GNOME *Background Apps*.

## 🧱 Architecture

A background daemon (`src/daemon/`) owns the engine and a control channel; a thin
GUI (`src/ui/`) and controller (`src/controller/`) talk to it over IPC. The shared
engine lifecycle is `src/engine-runner.vala` (also used by the Android host, which
runs in-process). Platform integration (tray, IPC, autostart, Android background)
lives in [libstation](https://github.com/Ampernic/libstation).

## 🔒 Security

Message security comes from **MTProto** itself (end-to-end between the client and
the data centre). The proxy and its TLS are only an obfuscation wrapper. See the
[mtproxy-ws core](https://github.com/Another-TGProxy/mtproxy-ws#-security) for details.

## ⚠️ Multi-threaded downloads in Telegram forks

Client forks (ExteraGram, Nagram and others) offer a "download speed boost": the
file is split into one-megabyte chunks and fetched over a dozen streams at once.
Over a direct connection that is a win; through a proxy each stream is a separate
TLS session that has to come up alongside the rest. The client does not wait that
long — it cancels the requests, the answers arrive when nobody needs them
(`received chunk but definitely cancelled` in its log), the video never plays,
and the proxy ends up looking broken, down to the "proxy is not configured
correctly and will be disabled" dialog.

If large files stall while chats and images are fine, turn the booster off:
**ExteraGram → Settings → ExteraGram → Download speed → Off.** The official
client has no such mode and downloads fine through the very same proxy, which
makes it a quick way to tell a client problem from a proxy one.

## ⚠️ Another client left on an old secret

When the proxy's secret changes (a reinstall, a reset), a client still holding
the old one keeps hammering away: Telegram cannot tell a wrong secret from an
unreachable server, so it reconnects the moment each attempt is refused —
hundreds of times a second in practice. The client that does work starts
dropping out.

The app shows a banner for this and offers the current link. Re-add the proxy
in that client (or turn the proxy off there) and it stops.

## 📦 Distribution

- **Android.** The foreground service (`specialUse`) + battery-optimization
  exemption are restricted on Google Play, so the build targets sideload / a
  personal repo rather than Play. The APK is release-signed.
- **macOS / Windows.** The `.dmg` and `setup.exe` are unsigned / un-notarized. On
  macOS, allow it under *System Settings → “Privacy & Security”*.

## 📄 License

[GPL-3.0-or-later](LICENSE).

<div align="center"><sub>Part of <b><a href="https://github.com/Another-TGProxy">Another TGProxy</a></b></sub></div>
