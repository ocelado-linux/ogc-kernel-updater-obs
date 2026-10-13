# ogc-handheld automation

`update-ogc-kernel.yml` runs every day on GitHub Actions:

1. Looks up the newest mainline OGC kernel tag (`vX.Y.Z-ogcN`) in
   OpenGamingCollective/linux (LTS tags are ignored).
2. Checks out `kernel-ogc` from `home:Luthenis:ogc-handheld` on OBS.
3. If upstream is newer, updates `Version`/`ogcrev` in `kernel-ogc.spec` and the
   tarball URL in `_service`, and commits. OBS then downloads and builds it.

## Setup
Repository → Settings → Secrets and variables → Actions → New repository secret:
- `OBS_USER`: your OBS user (Luthenis)
- `OBS_PASSWORD`: your OBS password

Manual run: Actions → "Update OGC kernel on OBS" → Run workflow.
Local dry run: `DRY_RUN=1 scripts/update-kernel-ogc.sh` (needs osc configured).
