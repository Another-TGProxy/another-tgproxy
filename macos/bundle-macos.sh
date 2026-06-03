#!/usr/bin/env bash
# Build another-tgproxy and assemble a self-contained .app + .dmg for macOS.
# Expects core (mtproxy-ws) sources under $CORE_SRC (default ../_core) and runs
# from the gui repo root. Homebrew provides gtk4/libadwaita/vala/etc.
set -euo pipefail
cd "$(dirname "$0")/.."

BREW="$(brew --prefix)"
CORE_SRC="${CORE_SRC:-_core}"
INSTALL="$PWD/_install"          # staging prefix for core + gui
DIST="$PWD/dist"

APP_NAME="Another TGProxy"
BIN="another-tgproxy"
APP_ID="space.ampernic.AnotherTGProxy"
APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"
FW="$CONTENTS/Frameworks"

info() { echo "==> $*"; }

# openssl@3 is keg-only - expose it to the compiler/linker (core uses find_library).
SSL="$(brew --prefix openssl@3)"
export PKG_CONFIG_PATH="$INSTALL/lib/pkgconfig:$SSL/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export LIBRARY_PATH="$SSL/lib:${LIBRARY_PATH:-}"
export CPATH="$SSL/include:${CPATH:-}"
export XDG_DATA_DIRS="$BREW/share"
# gettext (msgfmt) is keg-only; meson i18n needs it on PATH.
export PATH="$(brew --prefix gettext)/bin:$BREW/bin:$PATH"

# valac looks in share/vala-X.Y/vapi but Homebrew installs to share/vala/vapi.
VALA_VER="$(valac --version | awk '{print $2}')"
VAPI_DST="$BREW/Cellar/vala/$VALA_VER/share/vala-${VALA_VER%.*}/vapi"
if [ -d "$VAPI_DST" ]; then
  for f in "$BREW/share/vala/vapi"/*; do
    t="$VAPI_DST/$(basename "$f")"; [ -e "$t" ] || ln -s "$f" "$t"
  done
fi

# -- 1. Build core + gui into the staging prefix -------------------------------
info "Building core (mtproxy-ws)..."
rm -rf "$INSTALL"
meson setup "$CORE_SRC/_b" "$CORE_SRC" --prefix="$INSTALL" --buildtype=release -Dservice=false
meson install -C "$CORE_SRC/_b"

info "Building gui (another-tgproxy)..."
meson setup build --prefix="$INSTALL" --buildtype=release
meson install -C build

# -- 2. .app skeleton ---------------------------------------------------------
info "Assembling $APP..."
chmod -R u+w "$DIST" 2>/dev/null || true; rm -rf "$DIST"
mkdir -p "$MACOS" "$RES" "$FW"
cp "$INSTALL/bin/$BIN" "$MACOS/$BIN"

# -- 3. Vendor all non-system dylibs (incl. libmtproxyws) into Frameworks ------
info "Bundling dylibs with dylibbundler..."
dylibbundler -cd -of -b \
  -x "$MACOS/$BIN" \
  -d "$FW" -p "@executable_path/../Frameworks/"

# -- 4. GTK runtime: gdk-pixbuf loaders, GIO modules, schemas ------------------
info "Bundling gdk-pixbuf loaders (SVG icons need librsvg)..."
PIXBUF_VER=2.10.0
PIXBUF_DST="$RES/lib/gdk-pixbuf-2.0/$PIXBUF_VER/loaders"
mkdir -p "$PIXBUF_DST"
cp "$BREW"/lib/gdk-pixbuf-2.0/$PIXBUF_VER/loaders/*.so "$PIXBUF_DST/" 2>/dev/null || true
for so in "$PIXBUF_DST"/*.so; do
  dylibbundler -cd -of -b -x "$so" -d "$FW" -p "@executable_path/../Frameworks/" || true
done
GDK_PIXBUF_MODULEDIR="$PIXBUF_DST" \
  "$BREW/bin/gdk-pixbuf-query-loaders" > "$RES/lib/gdk-pixbuf-2.0/$PIXBUF_VER/loaders.cache"
# rewrite the absolute loader paths to a bundle-relative marker the launcher fixes up
sed -i '' "s|$RES|@RES@|g" "$RES/lib/gdk-pixbuf-2.0/$PIXBUF_VER/loaders.cache" || true

info "Bundling GIO modules..."
GIO_DST="$RES/lib/gio/modules"; mkdir -p "$GIO_DST"
cp "$BREW"/lib/gio/modules/*.so "$GIO_DST/" 2>/dev/null || true
for so in "$GIO_DST"/*.so; do
  dylibbundler -cd -of -b -x "$so" -d "$FW" -p "@executable_path/../Frameworks/" || true
done

info "Compiling GSettings schemas (GTK4 + Adwaita)..."
SCHEMAS="$RES/glib-2.0/schemas"; mkdir -p "$SCHEMAS"
cp "$BREW"/share/glib-2.0/schemas/org.gtk.gtk4.Settings*.xml "$SCHEMAS/" 2>/dev/null || true
cp "$BREW"/share/glib-2.0/schemas/org.gnome.desktop.interface.gschema.xml "$SCHEMAS/" 2>/dev/null || true
"$BREW/bin/glib-compile-schemas" "$SCHEMAS"

# -- 5. Icons: our app icon + Adwaita symbolic + caches ------------------------
info "Bundling icons..."
mkdir -p "$RES/icons/hicolor/scalable/apps"
cp "$INSTALL/share/icons/hicolor/scalable/apps/$APP_ID.svg" \
   "$RES/icons/hicolor/scalable/apps/"
cp "$BREW/share/icons/hicolor/index.theme" "$RES/icons/hicolor/" 2>/dev/null || true
mkdir -p "$RES/icons/Adwaita"
cp -R "$BREW/share/icons/Adwaita/symbolic" "$RES/icons/Adwaita/" 2>/dev/null || true
cp "$BREW/share/icons/Adwaita/index.theme" "$RES/icons/Adwaita/" 2>/dev/null || true
"$BREW/bin/gtk4-update-icon-cache" -q -t -f "$RES/icons/hicolor" 2>/dev/null || true

# translations
cp -R "$INSTALL/share/locale" "$RES/" 2>/dev/null || true

# -- 6. .icns from the app SVG -------------------------------------------------
info "Generating .icns..."
ICONSET="$DIST/icon.iconset"; mkdir -p "$ICONSET"
for s in 16 32 64 128 256 512; do
  "$BREW/bin/rsvg-convert" -w $s -h $s \
    "$INSTALL/share/icons/hicolor/scalable/apps/$APP_ID.svg" \
    -o "$ICONSET/icon_${s}x${s}.png"
  d=$((s*2))
  "$BREW/bin/rsvg-convert" -w $d -h $d \
    "$INSTALL/share/icons/hicolor/scalable/apps/$APP_ID.svg" \
    -o "$ICONSET/icon_${s}x${s}@2x.png"
done
iconutil -c icns "$ICONSET" -o "$RES/$BIN.icns"
rm -rf "$ICONSET"

# -- 7. Info.plist -------------------------------------------------------------
APP_VERSION="$(awk -F\' '/version:/{print $2; exit}' meson.build)"
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$APP_ID</string>
  <key>CFBundleVersion</key><string>$APP_VERSION</string>
  <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
  <key>CFBundleExecutable</key><string>launcher</string>
  <key>CFBundleIconFile</key><string>$BIN.icns</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

# -- 8. launcher: set GTK runtime env, then exec the real binary ---------------
cat > "$MACOS/launcher" <<'LAUNCH'
#!/bin/sh
DIR="$(cd "$(dirname "$0")" && pwd)"
RES="$DIR/../Resources"
export XDG_DATA_DIRS="$RES/share:$RES"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export GSETTINGS_SCHEMA_DIR="$RES/glib-2.0/schemas"
export GIO_MODULE_DIR="$RES/lib/gio/modules"
export GDK_PIXBUF_MODULE_FILE="$RES/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"
# materialise bundle-relative loader paths
if grep -q '@RES@' "$GDK_PIXBUF_MODULE_FILE" 2>/dev/null; then
  sed "s|@RES@|$RES|g" "$GDK_PIXBUF_MODULE_FILE" > "$GDK_PIXBUF_MODULE_FILE.real"
  export GDK_PIXBUF_MODULE_FILE="$GDK_PIXBUF_MODULE_FILE.real"
fi
export XDG_DATA_DIRS="$RES:$RES/share"
exec "$DIR/another-tgproxy" "$@"
LAUNCH
chmod +x "$MACOS/launcher"

# -- 9. DMG --------------------------------------------------------------------
info "Creating DMG..."
ARCH="$(uname -m)"
DMG="$DIST/${BIN}-${APP_VERSION}-${ARCH}.dmg"
create-dmg --volname "$APP_NAME" --app-drop-link 420 180 \
  --icon "$APP_NAME.app" 140 180 --window-size 600 360 \
  "$DMG" "$APP" 2>/dev/null || \
  hdiutil create -volname "$APP_NAME" -srcfolder "$APP" -ov -format UDZO "$DMG"

echo "Done: $DMG"
