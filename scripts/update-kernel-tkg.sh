#!/usr/bin/env bash
# Prepare linux-tkg sources for the OBS package kernel-tkg (Ocelado Linux
# desktop kernels) and commit them when upstream moves:
#   - new kernel stable release supported by linux-tkg, or
#   - new linux-tkg commit (patches / tweaks)
#
# linux-tkg needs network (git fetch of the kernel), OBS builds have none,
# so the patched tree + .config files are produced here and uploaded:
#   linux-tkg-<ver>.tar.xz, config-v2, config-v3
#
# Base config: openSUSE Tumbleweed kernel-default (from a Tumbleweed
# container), then linux-tkg tweaks: BORE, 1000 Hz, tickless idle, GCC,
# -march=x86-64-v2 / x86-64-v3.
#
# Needs: git, docker, python3, xz, osc (configured)
# Env:   OBS_PROJECT, OBS_API, DRY_RUN=1 (prepare but do not commit),
#        FORCE=1 (rebuild even if nothing changed)
set -euo pipefail

OBS_PROJECT="${OBS_PROJECT:-home:Luthenis:ogc-handheld}"
OBS_API="${OBS_API:-https://api.opensuse.org}"
PKG="kernel-tkg"
TKG_REPO="https://github.com/Frogging-Family/linux-tkg.git"
WORK="${WORK:-$(mktemp -d)}"
cd "$WORK"

log() { echo "== $*"; }

# --- 1. linux-tkg and target kernel version ------------------------------
git clone -q --depth 1 "$TKG_REPO" tkg-src
TKG_COMMIT="$(git -C tkg-src rev-parse --short=12 HEAD)"
SERIES_SUPPORTED="$(ls tkg-src/linux-tkg-patches | grep -E '^[0-9]+\.[0-9]+$' | sort -V)"

# newest stable/longterm release (no mainline -rc) whose series tkg supports
VER="$(curl -fsSL https://www.kernel.org/releases.json | python3 -c '
import json, sys
supported = set(sys.argv[1].split())
rels = [r["version"] for r in json.load(sys.stdin)["releases"]
        if r["moniker"] in ("stable", "longterm") and not r.get("iseol")]
ok = [v for v in rels if ".".join(v.split(".")[:2]) in supported]
key = lambda v: [int(x) for x in v.split(".")]
print(sorted(ok, key=key)[-1] if ok else "")
' "$SERIES_SUPPORTED")"
[[ -n "$VER" ]] || { echo "No kernel release supported by linux-tkg found" >&2; exit 1; }
log "Target: linux $VER, linux-tkg $TKG_COMMIT"

# --- 2. current OBS state ----------------------------------------------------
osc -A "$OBS_API" checkout -o obs "$OBS_PROJECT" "$PKG" >/dev/null
spec="obs/$PKG.spec"
cur_ver="$(sed -n 's/^Version:[[:space:]]*//p' "$spec" | head -n1)"
cur_commit="$(sed -n 's/^%define[[:space:]]\+tkgcommit[[:space:]]\+//p' "$spec" | head -n1)"
cur_rel="$(sed -n 's/^%define[[:space:]]\+tkgrel[[:space:]]\+//p' "$spec" | head -n1)"
log "OBS: linux $cur_ver, linux-tkg $cur_commit (tkgrel $cur_rel)"

if [[ "$cur_ver" == "$VER" && "$cur_commit" == "$TKG_COMMIT" && -z "${FORCE:-}" ]]; then
    echo "Already up to date."; exit 0
fi
if [[ "$(printf '%s\n' "$cur_ver" "$VER" | sort -V | tail -n1)" != "$VER" ]]; then
    echo "OBS has a newer kernel ($cur_ver) than upstream target ($VER), nothing to do."; exit 0
fi
if [[ "$cur_ver" == "$VER" ]]; then new_rel=$((cur_rel + 1)); else new_rel=1; fi

# --- 3. openSUSE Tumbleweed kernel-default config ----------------------------
log "Fetching Tumbleweed kernel-default config"
docker run --rm registry.opensuse.org/opensuse/tumbleweed:latest bash -c '
    zypper -n --gpg-auto-import-keys -q in --no-recommends kernel-default >/dev/null 2>&1
    cat "$(ls -1 /usr/lib/modules/*-default/config | sort -V | tail -n1)"' > tumbleweed.config
grep -q '^CONFIG_BTRFS_FS=' tumbleweed.config || { echo "Bad Tumbleweed config" >&2; exit 1; }

# --- 4. kernel sources: fetched here (visible progress), tkg runs offline ----
KGIT="$WORK/kernel-git/linux-tkg/linux-kernel.git"
log "Fetching linux v$VER (shallow) from GitHub mirror"
git init -q --bare "$KGIT"
git -C "$KGIT" fetch --depth 1 --progress https://github.com/gregkh/linux.git \
    "refs/tags/v$VER:refs/tags/v$VER" 2>&1 | tr '\r' '\n' | grep -E 'Receiving|Resolving|done|error|fatal' | tail -5 || true
git -C "$KGIT" rev-parse -q --verify "refs/tags/v$VER" >/dev/null \
    || { echo "Kernel tag v$VER was not fetched" >&2; exit 1; }
du -sh "$KGIT"

# --- 5. run linux-tkg "config" once per CPU level ----------------------------
for lvl in v3 v2; do
    log "linux-tkg config for x86-64-$lvl"
    rm -rf "tkg-$lvl"; cp -a tkg-src "tkg-$lvl"
    cp tumbleweed.config "tkg-$lvl/tumbleweed.config"
    mkdir -p ~/.config/frogminer
    cat > ~/.config/frogminer/linux-tkg.cfg <<CFG
_distro="Generic"
_version="v$VER"
_offline="true"
_kernel_source_folder="$WORK/kernel-git"
_configfile="tumbleweed.config"
_cpusched="bore"
_compiler="gcc"
_lto_mode="no"
_processor_opt="x86-64-$lvl"
_timer_freq="1000"
_tickless="2"
_default_cpu_gov="schedutil"
_aggressive_ondemand="false"
_numadisable="false"
_ftracedisable="false"
_acs_override="false"
_mglru="true"
_fsync_backport="false"
_fsync_legacy="false"
_ntsync="false"
_misc_adds="true"
_glitched_base="true"
_zenify="true"
_compileroptlevel="1"
_sched_yield_type="1"
_rr_interval="default"
_preempt_rt=""
_menunconfig="0"
_diffconfig="false"
_config_fragments="false"
_modprobeddb="false"
_kernel_on_diet="false"
_user_patches="false"
_community_patches=""
_debugdisable="false"
_STRIP="true"
_random_trust_cpu="true"
_noccache="true"
# no "script" pseudo-terminal wrapper: with piped stdin (no TTY) it gets the
# whole run killed (exit 143)
_logging_use_script="no"
CFG
    # heartbeat: the kernel git fetch is silent for several minutes
    ( while sleep 60; do echo "   ... still working ($lvl, $(date +%H:%M))"; done ) &
    hb=$!
    # no pipefail here: "yes" always ends with SIGPIPE when install.sh exits
    ( set +o pipefail; cd "tkg-$lvl" && yes "" | timeout 40m ./install.sh config ) \
        || { kill "$hb" 2>/dev/null; echo "linux-tkg config failed for $lvl" >&2; tail -50 "tkg-$lvl"/logs/*.txt 2>/dev/null || true; exit 1; }
    kill "$hb" 2>/dev/null || true
    test -s "tkg-$lvl/linux-src-git/.config"
    cp "tkg-$lvl/linux-src-git/.config" "config-$lvl"
    grep -E '^CONFIG_(SCHED_BORE|HZ_1000|X86_64_VERSION|MZEN|GENERIC_CPU)' "config-$lvl" || true
done

# both trees must be identical apart from .config
if ! diff -rq --exclude=.git --exclude=.config --exclude='*.orig' \
        tkg-v3/linux-src-git tkg-v2/linux-src-git >/dev/null; then
    echo "::warning::v2 and v3 trees differ beyond .config; using the v3 tree"
fi

# --- 6. source tarball ------------------------------------------------------
log "Packing linux-tkg-$VER.tar.xz"
rm -f tkg-v3/linux-src-git/.config
tar --exclude=.git --owner=0 --group=0 --sort=name \
    --transform "s,^linux-src-git,linux-tkg-$VER," \
    -C tkg-v3 -cf - linux-src-git | xz -T0 -6 > "linux-tkg-$VER.tar.xz"
ls -lh "linux-tkg-$VER.tar.xz"

# --- 7. commit to OBS -------------------------------------------------------
rm -f obs/linux-tkg-*.tar.xz
cp "linux-tkg-$VER.tar.xz" config-v2 config-v3 obs/
sed -i -E "s/^(Version:[[:space:]]*).*/\1$VER/" "$spec"
sed -i -E "s/^(%define[[:space:]]+tkgcommit[[:space:]]+).*/\1$TKG_COMMIT/" "$spec"
sed -i -E "s/^(%define[[:space:]]+tkgrel[[:space:]]+).*/\1$new_rel/" "$spec"
grep -nE '^Version|^%define[[:space:]]+tkg' "$spec"

if [[ -n "${DRY_RUN:-}" ]]; then echo "(dry run, not committing)"; exit 0; fi
( cd obs && osc addremove && osc -A "$OBS_API" commit -m "linux-tkg $TKG_COMMIT, linux $VER" )
echo "Committed: OBS will build kernel-tkgv2 and kernel-tkgv3 ($VER-$new_rel)."
