#!/usr/bin/env bash
# Build another-tgproxy and assemble a self-contained .app + .dmg for macOS.
# Expects core (mtproxy-ws) sources under $CORE_SRC (default ../_core) and runs
# from the gui repo root. Homebrew provides gtk4/libadwaita/vala/etc.
set -euo pipefail
SELF="$(cd "$(dirname "$0")" && pwd)"   # packaging/macos (holds Info.plist.in, launcher)
cd "$SELF/../.."                        # gui repo root

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
# -L dereferences Homebrew's symlinks: share/icons/Adwaita is a link into the Cellar,
# so a plain cp -R would copy the link (broken once distributed) instead of the files.
cp -RL "$BREW/share/icons/Adwaita" "$RES/icons/Adwaita"
cp -RL "$BREW/share/icons/hicolor" "$RES/icons/hicolor" 2>/dev/null || true
mkdir -p "$RES/icons/hicolor/scalable/apps"
cp "$INSTALL/share/icons/hicolor/scalable/apps/$APP_ID.svg" \
   "$RES/icons/hicolor/scalable/apps/"
chmod -R u+w "$RES/icons"
# Drop any icon-theme.cache: a stale/foreign cache shadows real icons. With
# index.theme present GTK4 scans the directories directly and finds every icon.
find "$RES/icons" -name icon-theme.cache -delete 2>/dev/null || true
# self-check: prove the icons the UI references actually landed in the bundle
echo "    icon bundle self-check:"
for i in symbolic/status/network-offline-symbolic symbolic/status/network-transmit-receive-symbolic \
         symbolic/status/dialog-error-symbolic symbolic/places/user-home-symbolic \
         symbolic/mimetypes/text-x-generic-symbolic symbolic/actions/send-to-symbolic \
         symbolic/legacy/emblem-system-symbolic; do
  if [ -f "$RES/icons/Adwaita/$i.svg" ]; then echo "      OK       $i"; else echo "      MISSING  $i"; fi
done
echo "    index.theme symbolic dirs: $(grep -c '^\[symbolic' "$RES/icons/Adwaita/index.theme" 2>/dev/null || echo 0); total symbolic svgs: $(find "$RES/icons/Adwaita" -name '*-symbolic.svg' | wc -l | tr -d ' ')"

# menu-bar tray icon: a template PNG from the app's symbolic glyph (same as the extension)
"$BREW/bin/rsvg-convert" -w 36 -h 36 \
  data/icons/hicolor/scalable/actions/another-tgproxy-symbolic.svg \
  -o "$RES/tray-icon.png" 2>/dev/null || true

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

# -- 7. Info.plist (from template) + launcher (static) -------------------------
APP_VERSION="$(awk -F\' '/version:/{print $2; exit}' meson.build)"
sed -e "s|@APP_NAME@|$APP_NAME|g" -e "s|@APP_ID@|$APP_ID|g" \
    -e "s|@VERSION@|$APP_VERSION|g" -e "s|@BIN@|$BIN|g" \
    "$SELF/Info.plist.in" > "$CONTENTS/Info.plist"

install -m 0755 "$SELF/launcher" "$MACOS/launcher"

# -- 9. DMG --------------------------------------------------------------------
info "Creating DMG..."
ARCH="$(uname -m)"
DMG="$DIST/${BIN}-${APP_VERSION}-${ARCH}.dmg"
create-dmg --volname "$APP_NAME" --app-drop-link 420 180 \
  --icon "$APP_NAME.app" 140 180 --window-size 600 360 \
  "$DMG" "$APP" 2>/dev/null || \
  hdiutil create -volname "$APP_NAME" -srcfolder "$APP" -ov -format UDZO "$DMG"

echo "Done: $DMG"
