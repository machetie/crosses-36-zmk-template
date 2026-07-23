#!/usr/bin/env bash
# Quick local ZMK build helper for the crosses keyboard.
#
# Usage: ./zmk-build.sh <shield> [board] [snippet] [-- <extra cmake args>]
#        ./zmk-build.sh --collect
#
# Examples:
#   ./zmk-build.sh crosses_left
#   ./zmk-build.sh crosses_right
#   ./zmk-build.sh "crosses_dongle dongle_screen" xiao_ble//zmk studio-rpc-usb-uart
#   ./zmk-build.sh settings_reset xiao_ble//zmk
#   ./zmk-build.sh settings_reset nice_nano@2//zmk
#   ./zmk-build.sh --collect

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Collect all previously built zmk.uf2 files into a single firmware/ directory.
collect_outputs() {
    local output_dir="$SCRIPT_DIR/firmware"
    echo "=== Collecting firmware outputs into $output_dir ==="
    rm -rf "$output_dir"
    mkdir -p "$output_dir"

    local count=0
    for uf2 in "$SCRIPT_DIR"/build/*/zephyr/zmk.uf2; do
        [ -f "$uf2" ] || continue
        local build_name
        build_name=$(basename "$(dirname "$(dirname "$uf2")")")
        local dest="$output_dir/${build_name}.uf2"
        cp "$uf2" "$dest"
        echo "  $build_name -> $dest"
        count=$((count + 1))
    done

    echo "=== Collected $count firmware file(s) ==="
}

if [ "$1" = "--collect" ]; then
    collect_outputs
    exit 0
fi

SHIELD="${1:-crosses_left}"
BOARD="${2:-nice_nano@2//zmk}"
SNIPPET="${3:-}"
set -- "${@:4}"

CMAKE_EXTRA=()
if [ "$1" = "--" ]; then
    shift
    CMAKE_EXTRA+=("$@")
fi

BUILD_DIR="build/$(echo "$SHIELD" | tr ' ' '_')_$(echo "$BOARD" | tr '/@' '__')${SNIPPET:+_${SNIPPET//-/_}}"

VENV="$HOME/Documents/git/zmk-workspace-venv"

export ZEPHYR_BASE="$SCRIPT_DIR/zephyr"
export ZEPHYR_SDK_INSTALL_DIR=/opt/zephyr-sdk-0.16.5-1
export ZEPHYR_TOOLCHAIN_VARIANT=zephyr

source "$VENV/bin/activate"

cd "$SCRIPT_DIR"

# CI treats the repo as a ZMK extra module using the committed `zephyr/module.yml`
# which declares board_root: . (to find boards/shields/).
# Locally, `west update` has placed the real Zephyr RTOS at ./zephyr/, overwriting
# the committed module.yml. We work around this by creating a staging dir that
# mirrors only the git-tracked files so the module.yml is intact.
STAGING_DIR="$SCRIPT_DIR/build/.module-staging"
echo "=== Preparing module staging dir for ZMK_EXTRA_MODULES ==="
rm -rf "$STAGING_DIR"
git -C "$SCRIPT_DIR" checkout-index -a --prefix="$STAGING_DIR/"

echo "=== Building shield=$SHIELD board=$BOARD ==="
echo "=== Build dir: $BUILD_DIR ==="

SNIPPET_ARGS=()
if [ -n "$SNIPPET" ]; then
    SNIPPET_ARGS=(-S "$SNIPPET")
    CMAKE_EXTRA+=(-DCONFIG_ZMK_STUDIO=y)
fi

# Dongle builds are always the central role in this repo.
if [[ "$SHIELD" == crosses_dongle* ]]; then
    CMAKE_EXTRA+=(-DCONFIG_ZMK_SPLIT_ROLE_CENTRAL=y)
fi

west build -s zmk/app -d "$BUILD_DIR" -b "$BOARD" "${SNIPPET_ARGS[@]}" -- \
    -DZMK_CONFIG="$SCRIPT_DIR/config" \
    -DSHIELD="$SHIELD" \
    -DZMK_EXTRA_MODULES="$STAGING_DIR" \
    "${CMAKE_EXTRA[@]}" \
    2>&1

echo "=== Build complete: $BUILD_DIR/zephyr/zmk.uf2 ==="
