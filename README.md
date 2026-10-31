# Ocelado Linux – OBS automation

GitHub Actions workflow that keeps the Ocelado Linux packages on the Open Build
Service ([`home:Luthenis:ogc-handheld`](https://build.opensuse.org/project/show/home:Luthenis:ogc-handheld))
up to date with their upstreams. OBS then rebuilds the packages and the images.

Workflow: `.github/workflows/update-ogc-kernel.yml` – runs every day at 05:17 UTC
and on demand (Actions → *Update Ocelado packages on OBS* → **Run workflow**).

## What it updates

### Job `update`

| Script | OBS package | Upstream | What it does |
|---|---|---|---|
| `scripts/update-kernel-ogc.sh` | `kernel-ogc` | [OpenGamingCollective/linux](https://github.com/OpenGamingCollective/linux) | Finds the newest mainline tag `vX.Y.Z-ogcN` (LTS tags ignored); updates `Version`/`ogcrev` in the spec and the tarball URL in `_service`. |
| `scripts/update-jupiter-hw-support.sh` | `jupiter-hw-support` | [evlav/jupiter-hw-support](https://github.com/evlav/jupiter-hw-support) | Tracks the SteamOS **3.8** series (`jupiter-3.8-YYYYMMDD.N`) and updates the `revision` in `_service`. Newer series (3.9+) renamed the polkit helpers to `holo-*` and need porting: their existence is reported as a **warning** in the run. |
| `scripts/update-steam-bootstrap.sh` | `steam-jupiter-bootstrap` | Valve's `steam-jupiter-stable` PKGBUILD ([evlaV/jupiter](https://github.com/evlaV/jupiter)) | Reads the fully bootstrapped Steam client file name (`_fat_bootstrap`) and updates the spec `Version` and the download URL in `_service`. |

Each step runs even if a previous one failed (`if: always()`).

### Job `tkg`

| Script | OBS package | Upstream |
|---|---|---|
| `scripts/update-kernel-tkg.sh` | `kernel-tkg` (builds `kernel-tkgv2` and `kernel-tkgv3`) | [Frogging-Family/linux-tkg](https://github.com/Frogging-Family/linux-tkg) + kernel.org |

OBS builds have no network and linux-tkg needs it, so this job prepares the
sources itself:

1. Picks the newest stable/longterm kernel whose series linux-tkg supports.
2. Takes the openSUSE Tumbleweed `kernel-default` config (from a Tumbleweed container) as base.
3. Runs `install.sh config` twice (`-march=x86-64-v3` and `x86-64-v2`) with:
   BORE scheduler, GCC (no LTO), 1000 Hz, tickless idle, `schedutil`,
   Glitched/Zenify tweaks.
4. Uploads `linux-tkg-<version>.tar.xz`, `config-v2` and `config-v3` to OBS and
   bumps `Version` / `tkgcommit` / `tkgrel` in the spec.

It runs when the kernel version or the linux-tkg commit changes. Takes about
20–40 minutes; OBS then needs a couple of hours to build both kernels.

## Setup

Repository → Settings → Secrets and variables → Actions → **New repository secret**:

- `OBS_USER`: OBS user (`Luthenis`)
- `OBS_PASSWORD`: OBS password

## Local runs

All scripts need `osc` configured with OBS credentials.

```sh
DRY_RUN=1 scripts/update-kernel-ogc.sh            # show what would change
DRY_RUN=1 scripts/update-jupiter-hw-support.sh
DRY_RUN=1 scripts/update-steam-bootstrap.sh
DRY_RUN=1 scripts/update-kernel-tkg.sh            # needs docker; prepares, does not commit
FORCE=1   scripts/update-kernel-tkg.sh            # rebuild tkg even if nothing changed
```

`update-kernel-ogc.sh`, `update-jupiter-hw-support.sh` and
`update-steam-bootstrap.sh` also accept `LOCAL_DIR=<package checkout>` to test
against a local copy without touching OBS.

## Notes

- A failed run with `HTTP Error 503` comes from OBS being temporarily
  unavailable; the next daily run retries.
- Versions never go backwards: if OBS already has a newer version than
  upstream, the scripts do nothing.
