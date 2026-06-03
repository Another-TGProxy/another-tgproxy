<div align="center">

<img src="data/icons/hicolor/scalable/apps/space.ampernic.AnotherTGProxy.svg" width="128" alt="логотип Another TGProxy"/>

# Another TGProxy

**GTK4 / libadwaita интерфейс и фоновый демон для движка `mtproxy-ws`.**

[![License](https://img.shields.io/badge/license-GPL--3.0--or--later-1C71D8.svg)](LICENSE)
![Toolkit](https://img.shields.io/badge/GTK4-libadwaita-37c871.svg)
![Language](https://img.shields.io/badge/Vala-7239b3.svg)
![Platform](https://img.shields.io/badge/platform-Linux-lightgrey.svg)

**Русский** · [English](README.en.md)

</div>

---

Нативное десктоп-приложение для прокси Telegram MTProto↔WebSocket
**[mtproxy-ws](https://github.com/Another-TGProxy/mtproxy-ws)**. Запускает прокси
как фоновый демон без окна и даёт окно управления: живой статус (активные
соединения, трафик), ссылку `tg://proxy`, настройки и просмотр лога.

<div align="center">

<img src="data/screenshots/home.png" width="49%" alt="Главная"/>
<img src="data/screenshots/settings.png" width="49%" alt="Настройки"/>

</div>

## 🖥️ Режимы вывода статуса

Прокси работает **фоновым демоном**, отдельным от окна, — закрытие окна не
останавливает прокси. Где показывать его живой статус, выбирается в Настройках.
Приложение определяет в рантайме **систему, рабочий стол и способ поставки** и
предлагает только реально доступные режимы (недоступные не показываются вовсе);
по умолчанию берётся лучший: трей где есть → иначе фон → иначе окно.

| Режим | Что это | Где доступен |
|---|---|---|
| **Окно** | Статус только в окне приложения | везде (фолбэк) |
| **Трей** | Иконка в системном трее (SNI): меню действий, живой статус-заголовок, тултип при наведении | KDE/XFCE/Cinnamon/…, GNOME с расширением AppIndicator; нативно Windows/macOS |
| **Фон** | GNOME *«Фоновые приложения»* (XDG Background portal) с живой настраиваемой строкой статуса (`Telegram · {active} соед. · ↑{up} ↓{down}`) | Linux + GNOME + Flatpak |
| **Быстрые настройки** | Тоггл в Quick Settings GNOME (как у Caffeine) через отдельное **[расширение GNOME Shell](https://github.com/Another-TGProxy/another-tgproxy-extension)** | Linux + GNOME + установленное расширение |

> ⚙️ Режим **«Быстрые настройки»** обеспечивает отдельное
> **[расширение GNOME Shell](https://github.com/Another-TGProxy/another-tgproxy-extension)**:
> оно общается с демоном по D-Bus и добавляет переключатель с живым статусом прямо
> в системное меню. В Настройках приложения этот режим появляется и
> включает/выключает расширение, если оно установлено.

## 📦 Зависимости

- **`mtproxy-ws`** — ядро (`libmtproxyws` + заголовки + `mtproxy-ws.pc` +
  Vala-биндинг `mtproxy-ws.vapi`). **Соберите и установите его первым.**
- `gtk4`, `libadwaita-1` (≥ 1.7), `glib-2.0`, `gio-2.0`, `gio-unix-2.0`,
  `json-glib-1.0`, `vala`, `meson`, `ninja`, `blueprint-compiler`.

## 🔨 Сборка

```sh
# 1) собрать + установить ядро (отдельный пакет)
meson setup ../core/build ../core && sudo ninja -C ../core/build install
# 2) собрать GUI поверх него
meson setup build
ninja -C build
./build/tg-ws-proxy
```

| Опция | По умолчанию | Эффект |
|---|:---:|---|
| `-Dprofile=development` | `default` | Отдельный app-id `.Devel`, имя «(Devel)» и config-dir — dev-сборка не конфликтует с установленной. |

## 📦 Flatpak (рекомендуется)

Из репозитория [flatpak.ampernic.space](https://flatpak.ampernic.space):

```sh
flatpak remote-add --if-not-exists --user \
    ampernic https://flatpak.ampernic.space/ampernic.flatpakrepo
flatpak install --user ampernic space.ampernic.AnotherTGProxy          # //devel для dev-сборки
flatpak run space.ampernic.AnotherTGProxy
```

Локальная сборка из этого чекаута (единый манифест включает ядро как модуль;
плейсхолдеры коммитов заполняются текущим `main`):

```sh
flatpak install flathub org.gnome.Sdk//49 org.gnome.Platform//49 org.flatpak.Builder
sed -e "s/__CORE_COMMIT__/$(git ls-remote https://github.com/Another-TGProxy/mtproxy-ws.git main | cut -f1)/" \
    -e "s/__GUI_COMMIT__/$(git rev-parse HEAD)/" \
    gui/flatpak/space.ampernic.AnotherTGProxy.yml > /tmp/manifest.yml
flatpak run org.flatpak.Builder --user --install --force-clean build-flatpak /tmp/manifest.yml
```

Под Flatpak демон поднимается **отдельным flatpak-инстансом** (через D-Bus-активацию)
и переживает закрытие окна, появляясь в GNOME «Фоновые приложения».

## 🧱 Архитектура

- **`src/daemon/`** — фоновый `GApplication` (`…​.Daemon`, `IS_SERVICE`) с движком
  `TgWsProxy.Engine`, control-каналом на Unix-сокете, презентерами статуса
  (`tray.vala` — SNI-трей; Background-портал) и D-Bus-интерфейсом `Control1`
  (`control.vala`) для расширения. GUI — лишь контроллер.
- **`src/controller/`** — `client.vala` (клиент control-канала), `service.vala`
  (запуск демона через D-Bus-активацию + автозапуск).
- **`src/ui/`** — оболочка `window.vala` + экраны `home-view` / `settings-view` /
  `log-view` (Blueprint + `Gtk.Template`).
- **`src/platform.vala`** — детект ОС/окружения/поставки и доступных режимов.
- **`src/config.vala`** — `~/.config/AnotherTGProxy/config.json`.

## 🔒 Безопасность

Безопасность переписки обеспечивает сам **MTProto** (end-to-end между клиентом и
дата-центром). Прокси и его TLS — лишь обфусцирующая обёртка. Подробнее — в
[ядре mtproxy-ws](https://github.com/Another-TGProxy/mtproxy-ws#-безопасность).

## 📄 Лицензия

[GPL-3.0-or-later](LICENSE).

<div align="center"><sub>Часть <b><a href="https://github.com/Another-TGProxy">Another TGProxy</a></b></sub></div>
