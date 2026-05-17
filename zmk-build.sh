#!/usr/bin/env bash
# Quick local ZMK build helper
# Usage: ./zmk-build.sh <shield> [board]
# Examples:
#   ./zmk-build.sh crosses_left
#   ./zmk-build.sh crosses_right
#   ./zmk-build.sh "crosses_dongle dongle_screen" xiao_ble//zmk
#   ./zmk-build.sh crosses_dongle_bios xiao_ble//zmk

set -e

SHIELD="${1:-crosses_left}"
BOARD="${2:-nice_nano@2//zmk}"
BUILD_DIR="build/$(echo "$SHIELD" | tr ' ' '_')_$(echo "$BOARD" | tr '/@' '__')"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$HOME/Documents/git/zmk-workspace-venv"

export ZEPHYR_BASE="$SCRIPT_DIR/zephyr"
export ZEPHYR_SDK_INSTALL_DIR=/opt/zephyr-sdk-0.16.5-1
export ZEPHYR_TOOLCHAIN_VARIANT=zephyr

source "$VENV/bin/activate"

cd "$SCRIPT_DIR"

# CI treats the repo as a ZMK extra module using the committed `zephyr/module.yml`
# which declares board_root: . (to find boards/shields/).
# Locally, west update has placed the real Zephyr RTOS at ./zephyr/, overwriting
# the committed module.yml. We work around this by creating a staging dir that
# mirrors only the git-tracked files so the module.yml is intact.
STAGING_DIR="$SCRIPT_DIR/build/.module-staging"
echo "=== Preparing module staging dir for ZMK_EXTRA_MODULES ==="
rm -rf "$STAGING_DIR"
git -C "$SCRIPT_DIR" checkout-index -a --prefix="$STAGING_DIR/"

echo "=== Building shield=$SHIELD board=$BOARD ==="
echo "=== Build dir: $BUILD_DIR ==="

west build -s zmk/app -d "$BUILD_DIR" -b "$BOARD" -- \
    -DZMK_CONFIG="$SCRIPT_DIR/config" \
    -DSHIELD="$SHIELD" \
    -DZMK_EXTRA_MODULES="$STAGING_DIR" \
    2>&1
