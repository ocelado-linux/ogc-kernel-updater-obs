#!/usr/bin/env bash
# Check the latest OGC kernel release and, if it is newer than what the
# OBS package builds, update kernel-ogc.spec + _service and commit to OBS.
#
# Needs: git, osc (configured with credentials), sed, sort -V
# Env:   OBS_PROJECT (default home:Luthenis:ogc-handheld)
#        OBS_API     (default https://api.opensuse.org)
#        DRY_RUN=1   to only show what would change
set -euo pipefail

OBS_PROJECT="${OBS_PROJECT:-home:Luthenis:ogc-handheld}"
OBS_API="${OBS_API:-https://api.opensuse.org}"
PKG="kernel-ogc"
UPSTREAM="https://github.com/OpenGamingCollective/linux.git"
WORK="${WORK:-$(mktemp -d)}"

# latest mainline OGC tag: vX.Y.Z-ogcN  (LTS tags "-lts-ogcN" are ignored)
latest="$(git ls-remote --tags --refs "$UPSTREAM" 'v*-ogc*' \
    | awk -F/ '{print $3}' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+-ogc[0-9]+$' \
    | sort -V | tail -n1)"
[[ -n "$latest" ]] || { echo "No OGC tags found" >&2; exit 1; }
new_ver="${latest#v}"; new_ver="${new_ver%-ogc*}"
new_rev="${latest##*-ogc}"
echo "Latest upstream: $latest (Version $new_ver, ogcrev $new_rev)"

if [[ -n "${LOCAL_DIR:-}" ]]; then
    pkgdir="$LOCAL_DIR"          # for testing without OBS
else
    (cd "$WORK" && osc -A "$OBS_API" checkout -o "$PKG" "$OBS_PROJECT" "$PKG")
    pkgdir="$WORK/$PKG"
fi
spec="$pkgdir/$PKG.spec"
svc="$pkgdir/_service"

cur_ver="$(sed -n 's/^Version:[[:space:]]*//p' "$spec" | head -n1)"
cur_rev="$(sed -n 's/^%define[[:space:]]\+ogcrev[[:space:]]\+//p' "$spec" | head -n1)"
echo "OBS package:     v${cur_ver}-ogc${cur_rev}"

if [[ "$cur_ver" == "$new_ver" && "$cur_rev" == "$new_rev" ]]; then
    echo "Already up to date."
    exit 0
fi
# never go backwards
newest="$(printf '%s\n' "v${cur_ver}-ogc${cur_rev}" "$latest" | sort -V | tail -n1)"
if [[ "$newest" != "$latest" ]]; then
    echo "OBS package is newer than upstream latest, nothing to do."
    exit 0
fi

sed -i -E "s/^(Version:[[:space:]]*).*/\1${new_ver}/" "$spec"
sed -i -E "s/^(%define[[:space:]]+ogcrev[[:space:]]+).*/\1${new_rev}/" "$spec"
sed -i -E "s#archive/refs/tags/v[^\"<]+\.tar\.gz#archive/refs/tags/${latest}.tar.gz#" "$svc"
sed -i -E "s#<param name=\"filename\">linux-[^<]+\.tar\.gz#<param name=\"filename\">linux-${new_ver}-ogc${new_rev}.tar.gz#" "$svc"

echo "--- changes"
grep -nE '^Version:|^%define[[:space:]]+ogcrev' "$spec"
grep -n 'tar.gz' "$svc"

if [[ -n "${DRY_RUN:-}" || -n "${LOCAL_DIR:-}" ]]; then
    echo "(dry run, not committing)"
    exit 0
fi
(cd "$pkgdir" && osc -A "$OBS_API" commit -m "Update to OGC kernel ${latest}")
echo "Committed: OBS will download ${latest} and rebuild ${PKG}."
