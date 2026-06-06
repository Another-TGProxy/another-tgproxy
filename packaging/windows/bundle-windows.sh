#!/usr/bin/env bash
# Build another-tgproxy + the mtproxy-ws core under MSYS2/MinGW (ucrt64) and
# assemble a portable folder with the full GTK4 runtime, then zip it.
#   env: CORE_SRC = path to the mtproxy-ws checkout (default: _core)
# Run from the gui/ directory inside an MSYS2 ucrt64 shell.
set -euo pipefail

PREFIX="${MINGW_PREFIX:-/ucrt64}"
CORE_SRC="${CORE_SRC:-_core}"
STAGE="$PWD/_stage"          # meson install prefix (POSIX-style layout)
DIST="$PWD/dist/another-tgproxy"
BIN="another-tgproxy.exe"
PIXBUF_VER=2.10.0

info () { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

# Copy a PE's MinGW DLL dependencies (transitive) into $DIST/bin. grep finding
# nothing must not abort the script (set -e + pipefail), hence the guards.
copy_dll_deps () {
  local target="$1" dll
  for dll in $(ldd "$target" 2>/dev/null | awk '{print $3}' \
               | grep -iE "(^|/)ucrt64/bin/" | sort -u || true); do
    [ -f "$dll" ] && cp -n "$dll" "$DIST/bin/" || true
  done
}

# -- 1. Build core + gui into the staging prefix ------------------------------
info "Building core (mtproxy-ws)..."
rm -rf "$STAGE" "$PWD/dist"
meson setup "$CORE_SRC/_b" "$CORE_SRC" --prefix="$STAGE" --buildtype=release -Dservice=false
meson install -C "$CORE_SRC/_b"

info "Building gui (another-tgproxy)..."
export PKG_CONFIG_PATH="$STAGE/lib/pkgconfig:$STAGE/lib64/pkgconfig:${PKG_CONFIG_PATH:-}"
meson setup build --prefix="$STAGE" --buildtype=release
meson install -C build

# -- 2. Portable tree: bin/ (exe + DLLs), lib/, share/ ------------------------
info "Assembling portable folder..."
mkdir -p "$DIST/bin"
cp "$STAGE/bin/$BIN" "$DIST/bin/"
# The core DLL installs to lib/; place it beside the exe so Windows finds it.
find "$STAGE" -name 'libmtproxyws*.dll' -exec cp {} "$DIST/bin/" \;

info "Copying dependent DLLs..."
copy_dll_deps "$DIST/bin/$BIN"
for dll in "$DIST"/bin/*.dll; do copy_dll_deps "$dll"; done

# -- 3. gdk-pixbuf loaders (SVG symbolic icons need librsvg) -------------------
info "Bundling gdk-pixbuf loaders..."
LOADERS_DST="$DIST/lib/gdk-pixbuf-2.0/$PIXBUF_VER/loaders"
mkdir -p "$LOADERS_DST"
cp "$PREFIX/lib/gdk-pixbuf-2.0/$PIXBUF_VER/loaders/"*.dll "$LOADERS_DST/"
for dll in "$LOADERS_DST"/*.dll; do copy_dll_deps "$dll"; done
# Emit the cache with basenames (resolved relative to the loaders dir) so the
# bundle stays relocatable.
( cd "$LOADERS_DST" && GDK_PIXBUF_MODULEDIR=. \
    "$PREFIX/bin/gdk-pixbuf-query-loaders.exe" *.dll \
    | sed "s#.*/\([a-zA-Z0-9_-]*\.dll\)#\1#" \
    > "../loaders.cache" )

# -- 4. GSettings schemas -----------------------------------------------------
info "Compiling GSettings schemas..."
SCHEMAS="$DIST/share/glib-2.0/schemas"; mkdir -p "$SCHEMAS"
cp "$PREFIX/share/glib-2.0/schemas/"*.xml "$SCHEMAS/" 2>/dev/null || true
cp "$PREFIX/share/glib-2.0/schemas/"*.gschema.override "$SCHEMAS/" 2>/dev/null || true
"$PREFIX/bin/glib-compile-schemas.exe" "$SCHEMAS"

# -- 5. Icons: Adwaita + hicolor + our app icon -------------------------------
info "Bundling icons..."
ICONS="$DIST/share/icons"; mkdir -p "$ICONS"
cp -r "$PREFIX/share/icons/Adwaita" "$ICONS/"
cp -r "$PREFIX/share/icons/hicolor" "$ICONS/" 2>/dev/null || true
# Our own app + symbolic icons installed by the gui.
cp -r "$STAGE/share/icons/hicolor" "$ICONS/" 2>/dev/null || true
"$PREFIX/bin/gtk4-update-icon-cache.exe" -q -t -f "$ICONS/Adwaita" || true
"$PREFIX/bin/gtk4-update-icon-cache.exe" -q -t -f "$ICONS/hicolor" || true

# -- 6. Translations (our domain + GTK's own) ---------------------------------
info "Bundling translations..."
mkdir -p "$DIST/share/locale"
cp -r "$STAGE/share/locale/." "$DIST/share/locale/" 2>/dev/null || true
for mo in "$PREFIX"/share/locale/*/LC_MESSAGES/gtk40.mo; do
  [ -f "$mo" ] || continue
  lang=$(basename "$(dirname "$(dirname "$mo")")")
  mkdir -p "$DIST/share/locale/$lang/LC_MESSAGES"
  cp "$mo" "$DIST/share/locale/$lang/LC_MESSAGES/"
done

# -- 7. CA bundle (TLS verify for the CF path) --------------------------------
info "Bundling CA certificates..."
mkdir -p "$DIST/bin/ssl/certs"
for ca in "$PREFIX/ssl/certs/ca-bundle.crt" "$PREFIX/etc/ssl/certs/ca-bundle.crt" \
          "$PREFIX/ssl/cert.pem" "$PREFIX/etc/ssl/cert.pem"; do
  if [ -f "$ca" ]; then cp "$ca" "$DIST/bin/ssl/certs/ca-bundle.crt"; break; fi
done

# -- 8. Zip -------------------------------------------------------------------
info "Zipping..."
( cd "$PWD/dist" && zip -qr "../another-tgproxy-windows-x64.zip" "another-tgproxy" )
info "Done: another-tgproxy-windows-x64.zip"
