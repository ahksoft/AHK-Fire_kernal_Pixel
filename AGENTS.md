# AGENTS.md

## What this repo is

Build scripts and CI configuration for kernel builds (Poco X6 Pro / Duchamp).
This repo does **not** contain kernel source code. The kernel is cloned at build time from `ahksoft2/kernel_devices_google_common`.

All build logic lives in `build.sh` and `functions.sh`. Configs are in `configs/`. Patches are in `patches/` (KernelSU features) and `kernel-patches/` (BBRv3, NTSync, SUSFS, DroidSpaces).

## Lint / verify

There is no local test suite or typecheck. The only verification is bash syntax checking:

```bash
bash -n build.sh
bash -n functions.sh
bash -n configs/gki_defconfig.sh
```

CI runs `bash -n` on all `.sh` files. Run this before pushing.

## Key environment variables

The entire build is driven by env vars. `build.sh` will fail or produce wrong variants if these are wrong:

| Variable | Values | Purpose |
|---|---|---|
| `KSU` | `KSUN`, `KSU`, `SKSU` | Root solution provider |
| `KSU_SUSFS` | `true`/`false` | Enable SUSFS integration |
| `LTO` | `noneLTO`, `thinLTO`, `fullLTO` | LTO optimization level |
| `KERNEL_REPO` | URL | Kernel source repo (required, set by CI) |
| `KERNEL_BRANCH` | branch name | Kernel source branch |
| `TODO` | `kernel`, `defconfig` | Build kernel or just export defconfig |
| `TEST` | `yes`/`no` | Dry-run mode |
| `DROIDSPACES` | `true`/`false` | DroidSpaces support |
| `NH` | `true`/`false` | NetHunter support |
| `NM` | `true`/`false` | NoMount support |
| `CLEAN_LTO_CACHE` | `true`/`false` | Purge ThinLTO cache |
| `BUILD_MODE` | `action`/`release` | Upload as artifact or create GitHub release |

## SU Providers

| Value | Provider | Source |
|---|---|---|
| `KSUN` | KernelSU-Next | `KernelSU-Next/KernelSU-Next` (dev) or `pershoot/KernelSU-Next` (dev-susfs) |
| `KSU` | KernelSU | `tiann/KernelSU` (main) |
| `SKSU` | SukiSU-Ultra | `SukiSU-Ultra/SukiSU-Ultra` (builtin/main) |

## Build variants matrix

The CI workflow (`.github/workflows/build.yml`) selects the SU provider from a dropdown and builds the chosen variant plus an optional SUSFS variant.

## Gotchas

- **`functions.sh` overrides `curl`, `git`, `wget`, `bash`** with retry wrappers (5 attempts). If you add new commands that need retry logic, they must be exported with `export -f`.
- **Config assembly is sequential**: `configs/gki_defconfig.sh` appends fragments to the kernel defconfig based on env vars. Changing the order or missing a config file will silently drop features.
- **KernelSU with SUSFS uses a manual git workflow** (`build.sh:155-185`): it clones KernelSU, soft-resets, applies 5 patches, commits, then runs `setup.sh`. This is fragile — patches may break on upstream KernelSU changes.
- **SUSFS patches are external**: cloned from `gitlab.com/simonpunk/susfs4ksu` at build time, not vendored. Branch `gki-android14-6.1` is hardcoded.
- **Neutron Clang toolchain** is downloaded via `antman` at build time. The `CLANG_BIN` path is `$WORKDIR/neutron-clang/bin`.
- **Kernel source is shallow-cloned** (`--depth=1`). `git rev-parse --short HEAD` is used for the localversion suffix.
- **Release versions** are date-based: `vYY.MM.DD` + optional run number suffix.
- **Release repo** is `ahksoft/AHK-Fire_kernal_Pixel`. Create release step uses `softprops/action-gh-release` with `contents: write` permission.
