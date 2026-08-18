# Plan: Auto Mouse Layer via `&zip_temp_layer` (Temporary Layer Input Processor)

## Goal

Add an **auto-mouse layer (AML)**: when either trackball reports movement, ZMK
temporarily activates a mouse layer, then turns it off after a no-input timeout.
Use upstream ZMK's **Temporary Layer Input Processor** (`&zip_temp_layer` /
`zmk,input-processor-temp-layer`) instead of any external listener module or the
PMW3610 driver's `automouse-layer` property.

Reference: https://zmk.dev/docs/keymaps/input-processors/temp-layer

## Current-state findings (from repo inspection)

This repo has **three build targets, each with the pointer input reaching the
host in a different place**. The AML input-processor must be attached to the
listener that actually feeds HID for that target:

| Target | File | Active listener(s) | Notes |
|--------|------|--------------------|-------|
| Left half | `boards/shields/crosses/crosses_left.overlay` | overrides `&trackball_peripheral_split` input-processors | left trackball (reg 0) |
| Right half | `boards/shields/crosses/crosses_right.overlay` | overrides `&trackball_right_split` input-processors | right trackball (reg 1) |
| Dongle | `boards/shields/crosses_dongle/crosses_dongle.overlay` | `trackball_left_listener` + `trackball_right_listener` (`status = "okay"`) | both trackballs land here in dongle mode |

- Listeners are declared **disabled** in `boards/shields/crosses/crosses.dtsi`
  (`trackball_peripheral_listener`, `trackball_right_listener`) and enabled /
  redefined per target.
- `config/crosses.conf` and `boards/shields/crosses/crosses.conf` already set
  `CONFIG_ZMK_POINTING=y`. Good — no extra Kconfig needed for the processor.
- **No `automouse-layer` is set** on the PMW3610 nodes, so there is no
  conflicting AML implementation to remove. (Caveat only applies if one is added
  later.)
- The dongle is the primary HID host in this build; getting AML right on the
  dongle target is the most important case.

### CRITICAL: layer index vs. layer name

The `#define`s in `config/crosses.keymap` do **not** match the physical keymap
block order:

```
#define NAV_LAYER    1
#define SYM_LAYER    2
#define SYSTEM_LAYER 3
```

But the `keymap` node defines blocks in this order (index = position in file):

| Index | Block name | Contents |
|-------|-----------|----------|
| 0 | `Base` | letters + homerow mods |
| 1 | `Num`  | numbers / F-keys / BT |
| 2 | `Sym`  | symbols |
| 3 | `Nav`  | **mouse bindings** (`&mkp LCLK/RCLK/MCLK`, `&msc SCRL_*`, arrows) |

**The mouse bindings already live in the `Nav` block, which is layer index 3.**
So the AML target layer parameter must be **3**, not 1. Confirm this by counting
blocks before touching anything; if blocks are reordered later, update the index.

Decision to confirm with user (see "Open questions"):
- Reuse existing `Nav` (index 3) as the mouse layer, **or**
- Add a dedicated minimal mouse-only layer at a new index.

This plan assumes **reuse of `Nav` = index 3**.

## Implementation steps

### Step 1 — Define a shared AML processor node

Add a reusable `zmk,input-processor-temp-layer` node. Put it somewhere included
by all three targets. The cleanest shared location is
`boards/shields/crosses/crosses.dtsi` (included by both half overlays). The
dongle overlay does **not** include `crosses.dtsi`, so the node must also be
available there — either duplicate the node in the dongle overlay or move it to a
small shared include. Plan: define it in `crosses.dtsi` for the halves and add an
identical node in `crosses_dongle.overlay`.

Node definition (uses `/omit-if-no-ref/` so it costs nothing when unreferenced):

```dts
#include <zephyr/dt-bindings/input/input-event-codes.h>

/ {
    /omit-if-no-ref/ aml: aml {
        compatible = "zmk,input-processor-temp-layer";
        #input-processor-cells = <2>;

        // Do not activate AML until 250 ms after the last keypress
        require-prior-idle-ms = <250>;

        // Physical key positions that should NOT cancel AML.
        // TODO: fill with the mouse-click key positions on the Nav layer
        //       (0-based). Verify against thirty_six_transform (36 keys, 0..35).
        excluded-positions = <>;
    };
};
```

Parameters when referenced: `<&aml LAYER TIMEOUT_MS>` → e.g. `<&aml 3 3000>`.

### Step 2 — Determine `excluded-positions`

The 36-key layout positions are 0..35 (see `thirty_six_transform` map in
`crosses.dtsi` / dongle overlay). Identify the 0-based positions of the mouse
buttons on the Nav layer so pressing them does **not** cancel AML.

From the `Nav` block, row 2 has `&mkp RCLK &mkp MCLK &mkp LCLK` and scroll keys.
Map those visual positions to indices (row-major, 10 per top rows, 6 thumbs):

- Row 0: 0..9
- Row 1: 10..19
- Row 2: 20..29
- Thumbs: 30..35

Compute the exact indices for the click/scroll keys and list them. (Do this as a
concrete sub-task; do not guess in the final DTS.)

### Step 3 — Wire AML into the LEFT half target

File: `boards/shields/crosses/crosses_left.overlay`

Append `&aml 3 3000` to the existing `&trackball_peripheral_split`
input-processors chain (keep the existing scroll/rate-limit processors):

```dts
&trackball_peripheral_split {
  device = <&trackball_peripheral>;
  input-processors
    = <&zip_xy_to_scroll_mapper>
    , <&zip_scroll_scaler 1 2>
    , <&zip_ble_report_rate_limit>
    , <&aml 3 3000>;
};
```

Note: order matters. AML should see the pointer events; appending after the
existing processors is the safe default. If AML fails to trigger, try placing it
earlier in the chain.

### Step 4 — Wire AML into the RIGHT half target

File: `boards/shields/crosses/crosses_right.overlay`

```dts
&trackball_right_split {
  device = <&trackball_central>;
  input-processors = <&zip_ble_report_rate_limit>, <&aml 3 3000>;
};
```

### Step 5 — Wire AML into the DONGLE target (primary case)

File: `boards/shields/crosses_dongle/crosses_dongle.overlay`

The dongle uses two enabled listeners. Add the AML node (Step 1) into this
overlay, then add `input-processors` to both listeners:

```dts
    trackball_left_listener: trackball_left_listener {
        compatible = "zmk,input-listener";
        status = "okay";
        device = <&trackball_peripheral_split>;
        input-processors = <&aml 3 3000>;
    };

    trackball_right_listener: trackball_right_listener {
        compatible = "zmk,input-listener";
        status = "okay";
        device = <&trackball_right_split>;
        input-processors = <&aml 3 3000>;
    };
```

Ensure `#include <zephyr/dt-bindings/input/input-event-codes.h>` and
`#include <input/processors.dtsi>` are available in this overlay if the AML node
or codes require them. (`crosses.dtsi` currently pulls in
`input/processors.dtsi`; the dongle overlay does not, so add includes as needed.)

### Step 6 — Keymap sanity (usually no change)

File: `config/crosses.keymap`

- The `Nav` (index 3) layer already has mouse bindings, so no new layer is
  strictly required.
- Optional: confirm `&trans` on non-mouse keys behaves acceptably while AML is
  active (falls through to the base layer).
- Optional refinement: keep `ZMK_POINTING_DEFAULT_SCRL_VAL` and existing scroll
  scaling as-is.

### Step 7 — Config

No new Kconfig required (`CONFIG_ZMK_POINTING=y` already present in both
`config/crosses.conf` and `boards/shields/crosses/crosses.conf`). Do **not** add
`CONFIG_ZMK_POINTING_SMOOTH_SCROLLING` anywhere new; it's already in the shield
conf.

## Build & verify

Per `AGENTS.md`, build all six targets and collect firmware:

```bash
./zmk-build.sh crosses_left
./zmk-build.sh crosses_right
./zmk-build.sh "crosses_dongle dongle_screen" xiao_ble//zmk studio-rpc-usb-uart
./zmk-build.sh "crosses_dongle dongle_screen" xiao_ble//zmk
./zmk-build.sh settings_reset nice_nano@2//zmk
./zmk-build.sh settings_reset xiao_ble//zmk
./zmk-build.sh --collect
```

Verification checklist:
1. All targets compile (watch for `zip_temp_layer` / `aml` unresolved-reference
   errors — indicates a missing include or the node not visible to that target).
2. Confirm 6 `.uf2` files land in `firmware/`.
3. Dongle RAM at link time stays below ~90% (AML adds negligible RAM, but check).
4. Flash all devices from the same build; settings-reset if pairing misbehaves.

Functional test on hardware:
- Move a trackball → mouse layer (index 3) activates; `&mkp`/`&msc` keys work.
- Stop moving → layer auto-releases after ~3 s.
- Type normally → a stray trackball bump within 250 ms of a keypress does **not**
  flip to the mouse layer (`require-prior-idle-ms`).
- Hold a mouse-click key listed in `excluded-positions` → layer does not cancel.

## Rollback

- Remove the `&aml ...` entries from the three overlay files.
- Remove the `aml` node(s). Because it uses `/omit-if-no-ref/`, an unreferenced
  node is harmless, but remove for cleanliness.
- No Kconfig to revert.

## Open questions (confirm before implementing)

1. **Target layer**: reuse existing `Nav` (index **3**) as the mouse layer, or
   create a dedicated mouse-only layer at a new index? (Plan assumes reuse of 3.)
2. **Timeout**: 3000 ms acceptable, or prefer a shorter/longer no-input timeout?
3. **`require-prior-idle-ms`**: 250 ms okay, or tune to typing speed?
4. **`excluded-positions`**: which exact keys (click/scroll) should keep AML
   alive while held? Need the final 0-based index list.
5. **Left/right halves standalone**: do the halves ever run without the dongle
   (i.e. directly as HID)? If dongle-only in practice, Steps 3–4 are optional but
   still recommended for consistency.
