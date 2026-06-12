#!/usr/bin/env bash
# Build another-tgproxy under MSYS2/MinGW (ucrt64) and assemble a portable folder
# with the full GTK4 runtime, then zip it. The mtproxy-ws core and libstation are
# vendored meson subprojects (subprojects/*.wrap, pinned) built in-tree by the
# GUI's meson setup — no separate core build.
# Run from the gui/ directory inside an MSYS2 ucrt64 shell.
set -euo pipefail

PREFIX="${MINGW_PREFIX:-/ucrt64}"
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

# -- 1. Build gui (+ vendored core/libstation subprojects) into staging -------
info "Building gui (another-tgproxy)..."
rm -rf "$STAGE" "$PWD/dist"
# Displayed/file version: the release tag (RELEASE_VERSION, set by CI on a tag,
# leading "v" stripped) else the meson.build project version.
VERSION="${RELEASE_VERSION#v}"
[ -n "$VERSION" ] || VERSION=$(sed -n "s/.*version: '\([0-9.]*\)'.*/\1/p" meson.build | head -1)
# A tag is a release (default profile); an untagged branch build is "development"
# — the .Devel app-id/icon and the striped header so it never looks like a release.
PROFILE=development; [ -n "${RELEASE_VERSION:-}" ] && PROFILE=default
export PKG_CONFIG_PATH="$STAGE/lib/pkgconfig:$STAGE/lib64/pkgconfig:${PKG_CONFIG_PATH:-}"
# Only a tagged build pins -Drelease_version; an untagged build keeps meson's
# "<ver>-devel" so it reads as a snapshot and is offered the released betas.
RELOPT=""; [ -n "${RELEASE_VERSION:-}" ] && RELOPT="-Drelease_version=$VERSION"
meson setup build --prefix="$STAGE" --buildtype=release $RELOPT -Dprofile="$PROFILE"
meson install -C build

# -- 2. Portable tree: bin/ (exe + DLLs), lib/, share/ ------------------------
info "Assembling portable folder..."
mkdir -p "$DIST/bin"
cp "$STAGE/bin/$BIN" "$DIST/bin/"
# The core + libstation DLLs install under the staging prefix; place them beside
# the exe so Windows finds them (ldd resolves them to the prefix, not ucrt64, so
# copy_dll_deps' ucrt64 filter would skip them).
find "$STAGE" -name 'libmtproxyws*.dll' -exec cp {} "$DIST/bin/" \;
find "$STAGE" -name 'libstation*.dll' -exec cp {} "$DIST/bin/" \;

info "Copying dependent DLLs..."
copy_dll_deps "$DIST/bin/$BIN"
for dll in "$DIST"/bin/*.dll; do copy_dll_deps "$dll"; done

# GTK4 imports vulkan-1.dll for its Vulkan renderer. ldd on the CI runner resolves
# it to System32 (so the loop skips it), but a plain Windows install may not have
# it; ship the MinGW loader so the app starts (GTK falls back to GL/cairo with no
# GPU). Same idea for any other DLL that lives in ucrt64 but resolves to System32.
for sysdll in vulkan-1.dll; do
  [ -f "$PREFIX/bin/$sysdll" ] && cp -n "$PREFIX/bin/$sysdll" "$DIST/bin/" || true
done

# GLib spawns child processes (the GUI launches the --daemon) through these
# helper exes at runtime; ldd can't see them, so copy them explicitly.
for helper in "$PREFIX"/bin/gspawn-win*-helper.exe "$PREFIX"/bin/gspawn-win*-helper-console.exe; do
  [ -f "$helper" ] && cp -n "$helper" "$DIST/bin/" || true
done

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

# -- 3b. GIO modules (glib-networking = the TLS backend the update check needs) --
info "Bundling GIO modules (TLS backend)..."
GIO_MODULES="$DIST/lib/gio/modules"
mkdir -p "$GIO_MODULES"
cp "$PREFIX/lib/gio/modules/"*.dll "$GIO_MODULES/" 2>/dev/null || true
for dll in "$GIO_MODULES"/*.dll; do [ -f "$dll" ] && copy_dll_deps "$dll"; done

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

# -- 6. Translations (our domain + GTK's and libadwaita's own) ----------------
# libadwaita's catalog localizes the Adw widgets we use (e.g. the About dialog's
# Developer/Website/Report-an-Issue labels); without it they stay English.
info "Bundling translations..."
mkdir -p "$DIST/share/locale"
cp -r "$STAGE/share/locale/." "$DIST/share/locale/" 2>/dev/null || true
for domain in gtk40 libadwaita; do
  for mo in "$PREFIX"/share/locale/*/LC_MESSAGES/$domain.mo; do
    [ -f "$mo" ] || continue
    lang=$(basename "$(dirname "$(dirname "$mo")")")
    mkdir -p "$DIST/share/locale/$lang/LC_MESSAGES"
    cp "$mo" "$DIST/share/locale/$lang/LC_MESSAGES/"
  done
done

# -- 7. CA bundle (TLS verify for the CF path) --------------------------------
info "Bundling CA certificates..."
mkdir -p "$DIST/bin/ssl/certs"
for ca in "$PREFIX/ssl/certs/ca-bundle.crt" "$PREFIX/etc/ssl/certs/ca-bundle.crt" \
          "$PREFIX/ssl/cert.pem" "$PREFIX/etc/ssl/cert.pem"; do
  if [ -f "$ca" ]; then cp "$ca" "$DIST/bin/ssl/certs/ca-bundle.crt"; break; fi
done

# -- 8. Installer -------------------------------------------------------------
# Naming: AnotherTGProxy-<version>-windows-x86_64-setup.exe ($VERSION from above).
BASE="AnotherTGProxy-${VERSION:-0}-windows-x86_64"
ICON="$PWD/data/windows/another-tgproxy.ico"

if [ -n "${MAKENSIS:-}" ]; then
  info "Building installer (NSIS)..."
  src_w=$(cygpath -w "$DIST")
  icon_w=$(cygpath -w "$ICON")
  "$MAKENSIS" -DVERSION="$VERSION" -DSRCDIR="$src_w" -DICON="$icon_w" \
      -DOUTFILE="$(cygpath -w "$PWD/$BASE-setup.exe")" packaging/windows/setup.nsi
  info "Done: $BASE-setup.exe"
else
  info "MAKENSIS unset — falling back to a zip..."
  ( cd "$PWD/dist" && zip -qr "../$BASE.zip" "another-tgproxy" )
  info "Done: $BASE.zip"
fi
