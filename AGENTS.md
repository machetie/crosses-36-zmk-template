# Agent Notes: crosses-36-zmk-template

## Project type

ZMK keyboard firmware configuration for a 36-key split keyboard with:
- nice!nano v2 halves (`crosses_left`, `crosses_right`)
- Seeed XIAO BLE dongle (`crosses_dongle`)
- Dongle OLED display via `machetie/zmk-dongle-screen`
- PMW3610 trackballs on both halves

This repo is a ZMK **config module**, not the ZMK source itself. The real ZMK, Zephyr, and external modules are fetched by `west`.

## Active branch

- **`dev/dongle`** — current working branch, pushed to `origin/dev/dongle`.
- **`main`** — base branch using upstream ZMK; use this as the starting point for new work.

Avoid `dev/dongle-reimplementation`: it was deleted because it set `BT_MAX_CONN=2` / `BT_MAX_PAIRED=2` on the central dongle, which broke split peripheral pairing.

## How to build

Use the local helper:

```bash
./zmk-build.sh crosses_left
./zmk-build.sh crosses_right
./zmk-build.sh "crosses_dongle dongle_screen" xiao_ble//zmk
./zmk-build.sh settings_reset nice_nano@2//zmk
./zmk-build.sh settings_reset xiao_ble//zmk
./zmk-build.sh --collect   # copies all .uf2 files into firmware/
```

Requirements:
- Python venv at `~/Documents/git/zmk-workspace-venv`
- Zephyr SDK at `/opt/zephyr-sdk-0.16.5-1`
- Run `west update` whenever `config/west.yml` changes between branches.

The script stages git-tracked files into `build/.module-staging` so `ZMK_EXTRA_MODULES` points to a copy where the committed `zephyr/module.yml` is intact. `west update` overwrites `./zephyr/`, so pointing `ZMK_EXTRA_MODULES` directly at the repo root would lose the module declaration.

## Module / dependency rules

- Stay on **upstream ZMK** (`zmkfirmware/zmk`).
- Do not switch to the `cormoran` fork unless explicitly asked.
- External modules listed in `config/west.yml` are gitignored; they appear at repo root after `west update`.
- If a build complains about a missing module or a stale `zephyr/`, run `west update` first.

## Key files

| File | Purpose |
|------|---------|
| `config/west.yml` | West manifest: ZMK commit, external modules |
| `build.yaml` | GitHub Actions / CI build matrix |
| `config/crosses.keymap` | Keymap shared by halves and dongle |
| `config/crosses.conf` | Common Kconfig (applied to all shields) |
| `config/crosses_dongle.conf` | Dongle-specific Kconfig (display, USB, pointing) |
| `boards/shields/crosses/` | Left/right shield overlays and configs |
| `boards/shields/crosses_dongle/` | Dongle shield overlay |
| `zephyr/module.yml` | Tells Zephyr this repo is a module with `board_root: .` |
| `zmk-build.sh` | Local build helper |

## Known decisions / pitfalls

- **No ZMK Studio on `dev/dongle`**. It was stripped to keep the build simple and upstream-compatible. If Studio is requested, create a separate branch from `main` or add it carefully and verify dongle RAM usage.
- **Dongle RAM usage is ~85%** in the current config. If the dongle crashes or behaves strangely under load, reduce `CONFIG_LV_Z_VDB_SIZE` to free RAM.
- **BLE pairing failures** are almost always caused by `BT_MAX_CONN` / `BT_MAX_PAIRED` being too low on the central, or by stale bonds. Use `settings_reset` and reflash all devices from the same build.
- **Per-shield Kconfig warnings** (e.g., `ZMK_USB`, `ZMK_POINTING_SMOOTH_SCROLLING`, `ZMK_SPLIT_BLE_CENTRAL_BATTERY_*` being ignored on peripherals) are expected because `config/crosses.conf` applies to all shields. They do not break the build.

## Verification checklist for changes

1. Run `west update` if `config/west.yml` changed.
2. Build all five targets with `./zmk-build.sh`.
3. Run `./zmk-build.sh --collect` and confirm 5 `.uf2` files in `firmware/`.
4. For dongle changes, check the RAM percentage at link time (keep below ~90%).
5. For pairing issues: settings-reset all devices, reflash, power-cycle dongle first then halves.
