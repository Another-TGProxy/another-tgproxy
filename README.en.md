<div align="center">

<img src="data/icons/hicolor/scalable/apps/space.ampernic.AnotherTGProxy.svg" width="128" alt="Another TGProxy logo"/>

# Another TGProxy

**A GTK4 / libadwaita front-end & background daemon for the `mtproxy-ws` engine.**

[![License](https://img.shields.io/badge/license-GPL--3.0--or--later-1C71D8.svg)](LICENSE)
![Toolkit](https://img.shields.io/badge/GTK4-libadwaita-37c871.svg)
![Language](https://img.shields.io/badge/Vala-7239b3.svg)
![Platform](https://img.shields.io/badge/platform-Linux-lightgrey.svg)

[Русский](README.md) · **English**

</div>

---

A native desktop app for the
**[mtproxy-ws](https://github.com/Another-TGProxy/mtproxy-ws)** Telegram
MTProto↔WebSocket proxy. It runs the proxy as a headless background daemon and
gives you a window to control it: live status (active connections, traffic), the
`tg://proxy` link, settings and a log view.

<div align="center">

<img src="data/screenshots/home.png" width="49%" alt="Home"/>
<img src="data/screenshots/settings.png" width="49%" alt="Settings"/>

</div>

## 🖥️ Status display modes

The proxy runs as a **background daemon** independent of the window — closing the
window doesn't stop it. Where its live status is shown is chosen in Settings. The
app detects the **OS, desktop and delivery method** at runtime and offers only the
modes that actually work here (unavailable ones don't appear at all); by default it
picks the best: tray where present → else background → else window.

| Mode | What it is | Available on |
|---|---|---|
| **Window** | Status in the app window only | everywhere (fallback) |
| **Tray** | System-tray icon (SNI): action menu, live status header, hover tooltip | KDE/XFCE/Cinnamon/…, GNOME with the AppIndicator extension; natively Windows/macOS |
| **Background** | GNOME *Background Apps* (XDG Background portal) with a live, configurable status line (`Telegram · {active} conn. · ↑{up} ↓{down}`) | Linux + GNOME + Flatpak |
| **Quick Settings** | A GNOME Quick Settings toggle (à la Caffeine) via a separate **[GNOME Shell extension](https://github.com/Another-TGProxy/another-tgproxy-extension)** | Linux + GNOME + the extension installed |

> ⚙️ The **Quick Settings** mode is provided by a separate
> **[GNOME Shell extension](https://github.com/Another-TGProxy/another-tgproxy-extension)**:
> it talks to the daemon over D-Bus and adds a toggle with live status right in the
> system menu. In the app's Settings this mode appears and enables/disables the
> extension when it is installed.

## 📦 Dependencies

- **`mtproxy-ws`** — the core (`libmtproxyws` + headers + `mtproxy-ws.pc` + the
  `mtproxy-ws.vapi` Vala binding). **Build & install it first.**
- `gtk4`, `libadwaita-1` (≥ 1.7), `glib-2.0`, `gio-2.0`, `gio-unix-2.0`,
  `json-glib-1.0`, `vala`, `meson`, `ninja`, `blueprint-compiler`.

## 🔨 Build

```sh
# 1) build + install the core (separate package)
meson setup ../core/build ../core && sudo ninja -C ../core/build install
# 2) build the GUI against it
meson setup build
ninja -C build
./build/tg-ws-proxy
```

| Option | Default | Effect |
|---|:---:|---|
| `-Dprofile=development` | `default` | Separate `.Devel` app-id, "(Devel)" name and config dir, so a dev build never clashes with an installed one. |

## 📦 Flatpak (recommended)

From the [flatpak.ampernic.space](https://flatpak.ampernic.space) repository:

```sh
flatpak remote-add --if-not-exists --user \
    ampernic https://flatpak.ampernic.space/ampernic.flatpakrepo
flatpak install --user ampernic space.ampernic.AnotherTGProxy          # //devel for a dev build
flatpak run space.ampernic.AnotherTGProxy
```

Local build from this checkout (the single manifest bundles the core; the commit
placeholders are filled with the current `main`):

```sh
flatpak install flathub org.gnome.Sdk//49 org.gnome.Platform//49 org.flatpak.Builder
sed -e "s/__CORE_COMMIT__/$(git ls-remote https://github.com/Another-TGProxy/mtproxy-ws.git main | cut -f1)/" \
    -e "s/__GUI_COMMIT__/$(git rev-parse HEAD)/" \
    gui/flatpak/space.ampernic.AnotherTGProxy.yml > /tmp/manifest.yml
flatpak run org.flatpak.Builder --user --install --force-clean build-flatpak /tmp/manifest.yml
```

Under Flatpak the daemon starts as its **own flatpak instance** (via D-Bus
activation) and survives the window closing, showing up in GNOME *Background Apps*.

## 🧱 Architecture

- **`src/daemon/`** — the headless `GApplication` (`…​.Daemon`, `IS_SERVICE`) owning
  a `TgWsProxy.Engine`, a Unix-socket control channel, status presenters
  (`tray.vala` — SNI tray; the Background portal) and the `Control1` D-Bus interface
  (`control.vala`) for the extension. The GUI is just a controller.
- **`src/controller/`** — `client.vala` (control-channel client), `service.vala`
  (start the daemon via D-Bus activation + autostart).
- **`src/ui/`** — the `window.vala` shell + `home-view` / `settings-view` /
  `log-view` screens (Blueprint + `Gtk.Template`).
- **`src/platform.vala`** — OS / desktop / delivery and available-mode detection.
- **`src/config.vala`** — `~/.config/AnotherTGProxy/config.json`.

## 🔒 Security

Message security comes from **MTProto** itself (end-to-end between the client and
the data centre). The proxy and its TLS are only an obfuscation wrapper. See the
[mtproxy-ws core](https://github.com/Another-TGProxy/mtproxy-ws#-security) for details.

## 📄 License

[GPL-3.0-or-later](LICENSE).

<div align="center"><sub>Part of <b><a href="https://github.com/Another-TGProxy">Another TGProxy</a></b></sub></div>
