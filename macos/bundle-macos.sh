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

# dylibbundler search paths (librsvg etc. live in keg dirs it won't guess) and a
# closed stdin so a still-missing lib fails fast instead of hanging on its prompt.
RSVG="$(brew --prefix librsvg)"
DB="dylibbundler -cd -of -b -s $BREW/lib -s $RSVG/lib"
bundle_into() { $DB -x "$1" -d "$2" -p "@executable_path/../Frameworks/" </dev/null; }
# dylibbundler can't rewrite @rpath/* refs inside a dlopen'd plugin; repoint them
# at the bundle's Frameworks explicitly first.
fix_rpath_refs() {
  otool -L "$1" 2>/dev/null | awk '/@rpath\//{print $1}' | while read -r dep; do
    install_name_tool -change "$dep" \
      "@executable_path/../Frameworks/${dep##*/}" "$1" 2>/dev/null || true
  done
}

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
bundle_into "$MACOS/$BIN" "$FW"

# -- 4. GTK runtime: gdk-pixbuf loaders, GIO modules, schemas ------------------
info "Bundling gdk-pixbuf loaders (SVG icons need librsvg)..."
PIXBUF_VER=2.10.0
SYS_LOADERS="$BREW/lib/gdk-pixbuf-2.0/$PIXBUF_VER/loaders"
PIXBUF_DST="$RES/lib/gdk-pixbuf-2.0/$PIXBUF_VER/loaders"
mkdir -p "$PIXBUF_DST"
cp "$SYS_LOADERS"/*.so "$PIXBUF_DST/" 2>/dev/null || true
# Build the cache from the SYSTEM loaders (they resolve @rpath/librsvg via Homebrew),
# then rewrite the paths to the bundle. Querying the bundled copies would fail once
# their librsvg is repointed, dropping the svg loader -> broken symbolic icons.
"$BREW/bin/gdk-pixbuf-query-loaders" "$SYS_LOADERS"/*.so \
  | sed "s|$SYS_LOADERS|@RES@/lib/gdk-pixbuf-2.0/$PIXBUF_VER/loaders|g" \
  > "$RES/lib/gdk-pixbuf-2.0/$PIXBUF_VER/loaders.cache"
# librsvg is referenced as @rpath/... which dylibbundler can't rewrite inside a
# plugin; copy it in and repoint the loaders at the bundle explicitly.
cp "$RSVG/lib/librsvg-2.2.dylib" "$FW/" 2>/dev/null || true
chmod u+w "$FW/librsvg-2.2.dylib" 2>/dev/null || true
for so in "$PIXBUF_DST"/*.so; do
  [ -e "$so" ] || continue
  fix_rpath_refs "$so"
  bundle_into "$so" "$FW" || true
done
# pull librsvg's own dependency tree into Frameworks
if [ -e "$FW/librsvg-2.2.dylib" ]; then
  fix_rpath_refs "$FW/librsvg-2.2.dylib"
  bundle_into "$FW/librsvg-2.2.dylib" "$FW" || true
fi

info "Bundling GIO modules (if any)..."
GIO_DST="$RES/lib/gio/modules"; mkdir -p "$GIO_DST"
cp "$BREW"/lib/gio/modules/*.so "$GIO_DST/" 2>/dev/null || true
for so in "$GIO_DST"/*.so; do
  [ -e "$so" ] || continue
  bundle_into "$so" "$FW" || true
done

info "Compiling GSettings schemas (GTK4 + Adwaita)..."
SCHEMAS="$RES/glib-2.0/schemas"; mkdir -p "$SCHEMAS"
cp "$BREW"/share/glib-2.0/schemas/org.gtk.gtk4.Settings*.xml "$SCHEMAS/" 2>/dev/null || true
cp "$BREW"/share/glib-2.0/schemas/org.gnome.desktop.interface.gschema.xml "$SCHEMAS/" 2>/dev/null || true
"$BREW/bin/glib-compile-schemas" "$SCHEMAS"

# -- 5. Icons: our app icon + Adwaita symbolic + caches ------------------------
info "Bundling icons..."
mkdir -p "$RES/icons"
# Whole Adwaita theme (symbolic layout varies between versions; copying it all is
# the only reliable way to get every -symbolic icon the UI references).
cp -R "$BREW/share/icons/Adwaita" "$RES/icons/" 2>/dev/null || \
  ditto "$BREW/share/icons/Adwaita" "$RES/icons/Adwaita"
cp -R "$BREW/share/icons/hicolor" "$RES/icons/" 2>/dev/null || true
mkdir -p "$RES/icons/hicolor/scalable/apps"
cp "$INSTALL/share/icons/hicolor/scalable/apps/$APP_ID.svg" \
   "$RES/icons/hicolor/scalable/apps/"
chmod -R u+w "$RES/icons"
# Drop any icon-theme.cache: a -t cache (or Homebrew's, built for its own paths) can
# shadow real icons so lookups fail. With index.theme present GTK4 scans the dirs
# directly and reliably finds every icon.
find "$RES/icons" -name icon-theme.cache -delete 2>/dev/null || true
echo "    bundled $(find "$RES/icons/Adwaita" -name '*-symbolic.svg' | wc -l | tr -d ' ') Adwaita symbolic icons"

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
# Materialise the loader cache (turn @RES@ into the real path) into a WRITABLE dir:
# the .app may live on a read-only DMG or in /Applications, so we can't write inside it.
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/Library/Caches}/space.ampernic.AnotherTGProxy"
mkdir -p "$CACHE_DIR"
sed "s|@RES@|$RES|g" "$RES/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache" > "$CACHE_DIR/loaders.cache"
export GDK_PIXBUF_MODULE_FILE="$CACHE_DIR/loaders.cache"
export XDG_DATA_DIRS="$RES:$RES/share"
# so the GUI can re-spawn itself as the background daemon (no /proc on macOS)
export ANOTHER_TGPROXY_EXE="$DIR/another-tgproxy"
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
