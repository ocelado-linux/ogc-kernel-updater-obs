#!/usr/bin/env bash
# Check the latest jupiter-hw-support tag of the tracked SteamOS series and,
# if it is newer than what the OBS package builds, update the revision in
# _service and commit to OBS.
#
# Only the SteamOS 3.8 series is tracked (tags jupiter-3.8-YYYYMMDD.N): newer
# series renamed the steamos-* polkit helpers to holo-* and need porting work.
# A newer series is reported as a warning so we know when it is time.
#
# Needs: git, osc (configured), sed, sort -V
# Env:   OBS_PROJECT, OBS_API, DRY_RUN=1, LOCAL_DIR (test without OBS)
#        SERIES (default 3.8)
set -euo pipefail

OBS_PROJECT="${OBS_PROJECT:-home:Luthenis:ogc-handheld}"
OBS_API="${OBS_API:-https://api.opensuse.org}"
PKG="jupiter-hw-support"
UPSTREAM="https://github.com/evlav/jupiter-hw-support.git"
SERIES="${SERIES:-3.8}"
WORK="${WORK:-$(mktemp -d)}"

tags="$(git ls-remote --tags --refs "$UPSTREAM" 'jupiter-3.*' | awk -F/ '{print $3}')"
re_series="^jupiter-${SERIES//./\\.}-[0-9]{8}\.[0-9]+$"
latest="$(grep -E "$re_series" <<<"$tags" | sort -V | tail -n1 || true)"
[[ -n "$latest" ]] || { echo "No jupiter-${SERIES}-* tags found" >&2; exit 1; }
echo "Latest upstream (SteamOS ${SERIES}): $latest"

# report newer SteamOS series (needs manual porting, holo-* helpers)
newer_series="$(grep -oE '^jupiter-3\.[0-9]+-' <<<"$tags" | sort -uV \
    | sed -E 's/^jupiter-(3\.[0-9]+)-$/\1/' \
    | awk -v s="$SERIES" '{ split($0,a,"."); split(s,b,"."); if (a[2]+0 > b[2]+0) print }' \
    | tail -n1)"
if [[ -n "$newer_series" ]]; then
    echo "::warning title=jupiter-hw-support::Newer SteamOS series ${newer_series} available upstream; still tracking ${SERIES} (needs porting to holo-* helpers)"
fi

if [[ -n "${LOCAL_DIR:-}" ]]; then
    pkgdir="$LOCAL_DIR"
else
    (cd "$WORK" && osc -A "$OBS_API" checkout -o "$PKG" "$OBS_PROJECT" "$PKG")
    pkgdir="$WORK/$PKG"
fi
svc="$pkgdir/_service"

current="$(sed -n 's#.*<param name="revision">\([^<]*\)</param>.*#\1#p' "$svc" | head -n1)"
echo "OBS package:     $current"

if [[ "$current" == "$latest" ]]; then
    echo "Already up to date."
    exit 0
fi
newest="$(printf '%s\n' "$current" "$latest" | sort -V | tail -n1)"
if [[ "$newest" != "$latest" ]]; then
    echo "OBS package is newer than upstream latest, nothing to do."
    exit 0
fi

sed -i "s#<param name=\"revision\">[^<]*</param>#<param name=\"revision\">${latest}</param>#" "$svc"
echo "--- changes"
grep -n 'revision' "$svc"

if [[ -n "${DRY_RUN:-}" || -n "${LOCAL_DIR:-}" ]]; then
    echo "(dry run, not committing)"
    exit 0
fi
(cd "$pkgdir" && osc -A "$OBS_API" commit -m "Update to ${latest}")
echo "Committed: OBS will fetch ${latest} and rebuild ${PKG}."
