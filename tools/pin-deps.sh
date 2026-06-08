#!/usr/bin/env bash
# Pin the vendored subproject revisions (core + libstation) to exact commits so
# a GUI tag builds one deterministic dependency set on every platform. The two
# .wrap files are the single source of truth for which core/libstation a build
# uses; bumping a dependency is one deliberate commit produced by this script.
#
# Usage:
#   tools/pin-deps.sh                     # pin both to their upstream branch HEAD
#   tools/pin-deps.sh --core <ref>        # pin core to a branch/tag/sha
#   tools/pin-deps.sh --station <ref>     # pin libstation to a branch/tag/sha
#   tools/pin-deps.sh --show              # print current pins and upstream HEADs
# Run from the gui/ checkout. Commits nothing — review the diff and commit.
set -euo pipefail

cd "$(dirname "$0")/.."
CORE_WRAP=subprojects/mtproxy-ws.wrap
STATION_WRAP=subprojects/libstation.wrap

url_of()  { sed -n 's/^url = //p' "$1" | head -1; }
rev_of()  { sed -n 's/^revision = //p' "$1" | head -1; }
# Resolve a ref (branch/tag/sha) to a full commit sha against a remote.
resolve() { # <url> <ref>
  local url="$1" ref="$2" sha
  case "$ref" in
    *[!0-9a-f]*|??????????????????????????????????????????????) : ;;  # not a 40-hex sha
  esac
  if [ "${#ref}" = 40 ] && [ -z "${ref//[0-9a-f]/}" ]; then echo "$ref"; return; fi
  sha=$(git ls-remote "$url" "$ref" "refs/heads/$ref" "refs/tags/$ref" 2>/dev/null | head -1 | cut -f1)
  [ -n "$sha" ] || { echo "cannot resolve '$ref' in $url" >&2; exit 1; }
  echo "$sha"
}
set_rev() { sed -i "s|^revision = .*|revision = $2|" "$1"; }  # <wrap> <sha>

CORE_REF=""; STATION_REF=""; SHOW=0
while [ $# -gt 0 ]; do
  case "$1" in
    --core)    CORE_REF="$2"; shift 2 ;;
    --station) STATION_REF="$2"; shift 2 ;;
    --show)    SHOW=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ "$SHOW" = 1 ]; then
  printf 'core      pinned=%s  upstream main=%s\n'   "$(rev_of "$CORE_WRAP")"    "$(resolve "$(url_of "$CORE_WRAP")" main)"
  printf 'libstation pinned=%s  upstream master=%s\n' "$(rev_of "$STATION_WRAP")" "$(resolve "$(url_of "$STATION_WRAP")" master)"
  exit 0
fi

# Default branch per dep when no ref is given.
core_sha=$(resolve "$(url_of "$CORE_WRAP")" "${CORE_REF:-main}")
station_sha=$(resolve "$(url_of "$STATION_WRAP")" "${STATION_REF:-master}")
set_rev "$CORE_WRAP" "$core_sha"
set_rev "$STATION_WRAP" "$station_sha"
printf 'pinned core      -> %s\n' "$core_sha"
printf 'pinned libstation -> %s\n' "$station_sha"
echo "review 'git diff subprojects/*.wrap' and commit."
