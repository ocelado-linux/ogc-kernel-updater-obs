#!/usr/bin/env bash
# Check Valve's latest "fat" Steam bootstrap (the one SteamOS ships in
# steam-jupiter-stable, read from Valve's PKGBUILD in the evlaV/jupiter
# mirror) and, if it is newer than the OBS package, update _service + spec
# and commit to OBS.
#
# Env: OBS_PROJECT, OBS_API, DRY_RUN=1, LOCAL_DIR (test without OBS)
set -euo pipefail

OBS_PROJECT="${OBS_PROJECT:-home:Luthenis:ogc-handheld}"
OBS_API="${OBS_API:-https://api.opensuse.org}"
PKG="steam-jupiter-bootstrap"
PKGBUILD_URL="${PKGBUILD_URL:-https://raw.githubusercontent.com/evlaV/jupiter/main/steam-jupiter-stable/PKGBUILD}"
WORK="${WORK:-$(mktemp -d)}"

file="$(curl -fsSL "$PKGBUILD_URL" | sed -n 's/^_fat_bootstrap=//p' | tr -d "\"'" | head -n1)"
[[ "$file" =~ ^steam_jupiter_stable_bootstrapped_([0-9]+\.[0-9]+)\.tar\.xz$ ]] \
    || { echo "Could not parse _fat_bootstrap from Valve PKGBUILD (got '$file')" >&2; exit 1; }
new_ver="${BASH_REMATCH[1]}"
echo "Latest Valve bootstrap: $file"

if [[ -n "${LOCAL_DIR:-}" ]]; then
    pkgdir="$LOCAL_DIR"
else
    (cd "$WORK" && osc -A "$OBS_API" checkout -o "$PKG" "$OBS_PROJECT" "$PKG")
    pkgdir="$WORK/$PKG"
fi
spec="$pkgdir/$PKG.spec"; svc="$pkgdir/_service"
cur_ver="$(sed -n 's/^Version:[[:space:]]*//p' "$spec" | head -n1)"
echo "OBS package:            $cur_ver"

if [[ "$cur_ver" == "$new_ver" ]]; then echo "Already up to date."; exit 0; fi
if [[ "$(printf '%s\n' "$cur_ver" "$new_ver" | sort -V | tail -n1)" != "$new_ver" ]]; then
    echo "OBS package is newer, nothing to do."; exit 0
fi

sed -i -E "s/^(Version:[[:space:]]*).*/\1${new_ver}/" "$spec"
sed -i -E "s#steam_jupiter_stable_bootstrapped_[0-9.]+\.tar\.xz#${file}#" "$svc"
echo "--- changes"; grep -n '^Version' "$spec"; grep -n 'tar.xz' "$svc"

if [[ -n "${DRY_RUN:-}" || -n "${LOCAL_DIR:-}" ]]; then echo "(dry run, not committing)"; exit 0; fi
# drop the old downloaded archive so OBS fetches the new one
(cd "$pkgdir" && for f in steam_jupiter_stable_bootstrapped_*.tar.xz; do
    [[ -e "$f" && "$f" != "$file" ]] && osc rm -f "$f" || true; done
 osc -A "$OBS_API" commit -m "Update to Valve Steam bootstrap ${new_ver}")
echo "Committed: OBS will download ${file} and rebuild ${PKG}."
