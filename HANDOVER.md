# Handover: crosses-36 ZMK firmware, branch `yolo`

Date: 2026-11-24. Repo: `machetie/crosses-36-zmk-template`. Read `AGENTS.md` first for build commands and repo rules.

## Hardware

- Two nice!nano v2 halves (`crosses_left`, `crosses_right`), each with a PMW3610 trackball (efogdev driver).
- Seeed XIAO BLE dongle (`crosses_dongle` + `dongle_screen` shield from `machetie/zmk-dongle-screen`).
- Both halves are BLE split **peripherals**; the dongle is the **central** and talks to the computer over USB.
- The user is on Linux. The dongle is plugged into a Dell WD19 dock. In `lsusb` it shows as `1d50:615e OpenMoko, Inc. Crosses`.

## Resolved (2026-11-24)

The user reflashed **only the dongle** from CI run 68 and everything works: keys, trackballs and the dongle screen. Two things changed at once, though: the run (66 → 68) **and the artifact (`crosses_dongle_studio` → `crosses_dongle_bios`)**. The halves are still on run 66 firmware (0 dBm), so TX power was not the cause. The dongle config is identical between runs 66 and 68, so the cause is one of:

1. the dongle's bond state being out of sync after the settings resets (reflashing cleared it), or
2. a problem with the **Studio** dongle build. Its RAM is 89.1% (BIOS: 84.8%), and it adds Studio RPC over USB-UART **and BLE**, plus `ZMK_STUDIO_LOCKING=y`. No smoking gun in the build log.

To tell them apart: flash `crosses_dongle_studio` from the same run onto the dongle. If input breaks again, it's the Studio build. Debug it with a Studio build plus `-DCONFIG_ZMK_STUDIO_TRANSPORT_BLE=n`, and/or by freeing RAM (`CONFIG_LV_Z_VDB_SIZE`).

- If this happens again: `settings_reset` all three, flash the halves, then flash the dongle **last**, then power-cycle the dongle first.
- `725ec2e` (TX back to +8 dBm) is still on the branch. That is the safer default, but 0 dBm on run 66 is working on the user's desk.
- The `crosses_dongle_debug_log` target in `build.yaml` can be removed once the setup has been stable for a while.

## Original problem (kept for reference)

After flashing `yolo` firmware (CI run 66) to all three devices:

1. At first the halves didn't connect at all. After `settings_reset` on all three plus a reflash, they paired.
2. **Now: no key presses or trackball movement reach the computer.** The dongle enumerates on USB fine. Holding a layer key on a half does **not** change the layer shown on the dongle screen, so events aren't reaching the dongle at all: the halves-to-dongle link is broken, not the dongle-to-computer link.
3. **After restarting the dongle, the halves don't reconnect.**

### Hypotheses, most likely first

1. **Weak radio link.** `yolo` had lowered the halves' TX power from +8 to 0 dBm, and the dongle sits in a dock. This is now reverted (commit `725ec2e`), but the reverted build has **not** been tested on hardware yet.
2. **Bond/encryption mismatch.** The link connects (battery levels can be read without encryption), but the split service needs encryption. If security fails, the dongle can't subscribe to key events. Restarting the dongle and failing to reconnect fits this too. The fix is `settings_reset` on all three and flashing all three from the **same** CI run.
3. Something else in the `yolo` changes to the halves (list below). Nothing there touches pairing, but none of it has been tested on hardware.

### Next steps (already given to the user)

1. Wait for CI runs 67/68 on `yolo` (run 68 = commit `725ec2e`, which includes everything).
2. Flash `settings_reset` on all three, then `crosses_left`, `crosses_right`, and **`crosses_dongle_debug_log`** on the dongle.
3. Plug the dongle into the laptop directly or via a short extension cable, not the dock.
4. Run `sudo cat /dev/ttyACM0`, power on the halves, press keys, then unplug and replug the dongle. Read the log for connection, security/encryption, discovery and subscription errors.
5. If it works with +8 dBm, the TX power change was the cause. Leave it at +8.
6. If it still fails, compare against `dev/dongle`. Its old CI artifacts have expired, so rebuild that branch, or bisect the `yolo` commits (each one is self-contained).

## What `yolo` changed (on top of `dev/dongle` @ `a5764ed`)

| Commit | Change |
|---|---|
| `78b2a98` | Pin ZMK `6e2ef41e…`, `zmk-pmw3610-driver` `38105b4f…`, `zmk-report-rate-limit` `06ba1e5d…`, `zmk-dongle-screen` `02c78a7d…`, and the CI workflow to the same ZMK SHA. Drop the unused `zmk-input-processor-xyz` module. These are the revisions of the last green `dev/dongle` build. |
| `fa2e4fa` | Split Kconfig by role. `config/crosses.conf` is merged into **all three** builds, after the shield confs (confirmed in CI logs), so it now holds only common settings. Halves-only settings go in `boards/shields/crosses/crosses_halves.conf`, and `crosses_left.conf`/`crosses_right.conf` are **symlinks** to it (confirmed loading in CI). Battery fetch/proxy moved to the dongle conf; the dongle keeps `ZMK_BATTERY_REPORTING=y` because the dongle-screen widget links against it. Deleted the never-loaded `boards/shields/crosses/crosses.conf`; its REST1/REST2 sample times (35/65 ms) now apply. Removed the unbound `rrl` behavior override. Kept only `boards/nice_nano_nrf52840_zmk.overlay`. Fixed: the dongle was getting `ZMK_SLEEP=y` from `config/crosses.conf`. |
| `81b29e1` | Trackball processing moved to the dongle (`crosses_dongle.overlay`). The halves only rate-limit and forward raw X/Y. Left listener: `zip_xy_to_scroll_mapper` + `zip_scroll_scaler 1 2`, no auto-mouse. Right listener: `aml 3 3000` (temp layer = Nav, layer 3, which has the mouse buttons) plus a `precision` child node on layer 2 (Sym, hold SPACE) with `zip_xy_scaler 1 3` and `process-next`. The user asked for **no separate mouse layer**. |
| `96e2b1e` | Dongle `CONFIG_USB_HID_POLL_INTERVAL_MS=1` (was 10). Halves `CONFIG_ZMK_INPUT_PROCESSOR_REPORT_RATE_LIMIT_DEFAULT=8` (was 2). |
| `e58bae1` | Halves `CONFIG_ZMK_DISPLAY=n` (OLEDs off, at the user's request). The OLED DT nodes are kept. |
| `d4862d4` | Removed `force-high-performance` from the right PMW3610 node (`force-awake` kept). |
| `03ccffc` | Halves TX power +8 → 0 dBm. **Reverted in `725ec2e`.** |
| `a4a56e2` | README/AGENTS docs for the new layout. |
| `7874688` | `build.yaml`: added the `crosses_dongle_debug_log` target (`zmk-usb-logging` snippet, `-DCONFIG_ZMK_LOGGING_MINIMAL=n`). Remove it once debugging is done. |

## Verified from CI logs (run 66)

- All 6 targets build.
- Dongle RAM is 84.8% (BIOS build), flash 79.8%.
- Dongle: `ZMK_SPLIT_ROLE_CENTRAL=y`, `ZMK_SPLIT_BLE_CENTRAL_PERIPHERALS=2`, `BT_MAX_CONN=6`, `BT_MAX_PAIRED=6`, `ZMK_USB=y`, HKRO boot protocol, poll 1 ms.
- Halves: peripheral, `BT_MAX_PAIRED=1`, `ZMK_SLEEP=y`, `ZMK_DISPLAY` off, rate limit 8.
- Kconfig merge order on the dongle: `prj.conf` → `crosses_dongle.conf` → `dongle_screen.conf` → `config/crosses.conf` → cmake `-D` args.

## Not tested on hardware

Everything in `yolo`: scroll and pointer behaviour, precision mode, auto-mouse, 8 ms batching, 1000 Hz polling, battery impact. Nothing has been confirmed working on the keyboard yet.

## Other branches

- `main`: original config. All halves of the split wiring are correct, but nothing is pinned.
- `dev/dongle`: the base of `yolo`; it last built green in Aug 2026. It has auto-mouse on both listeners and the dongle `ZMK_SLEEP` override bug.
- `dev/cormoran-studio`: cormoran ZMK fork. Don't use it unless asked (see `AGENTS.md`).
