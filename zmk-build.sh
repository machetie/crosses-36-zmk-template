#!/usr/bin/env bash
# Local ZMK build helper for the crosses keyboard.
#
# Usage: ./zmk-build.sh <shield> [board] [snippet] [-- <extra cmake args>]
#        ./zmk-build.sh "crosses_dongle dongle_screen" xiao_ble//zmk studio-rpc-usb-uart
#        ./zmk-build.sh --collect

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
set -- "${@:3}"

SNIPPET=""
CMAKE_EXTRA=()
if [ $# -gt 0 ]; then
    if [ "$1" = "--" ]; then
        shift
        CMAKE_EXTRA+=("$@")
    else
        SNIPPET="$1"
        shift
        if [ $# -gt 0 ] && [ "$1" = "--" ]; then
            shift
            CMAKE_EXTRA+=("$@")
        fi
    fi
fi

BUILD_DIR="build/$(echo "$SHIELD" | tr ' ' '_')_$(echo "$BOARD" | tr '/@' '__')${SNIPPET:+_$(echo "$SNIPPET" | tr '/@' '__')}"

VENV="$HOME/Documents/git/zmk-workspace-venv"

export ZEPHYR_BASE="$SCRIPT_DIR/zephyr"
export ZEPHYR_SDK_INSTALL_DIR=/opt/zephyr-sdk-0.16.5-1
export ZEPHYR_TOOLCHAIN_VARIANT=zephyr

source "$VENV/bin/activate"

cd "$SCRIPT_DIR"

# CI treats the repo as a ZMK extra module using the committed `zephyr/module.yml`.
# Locally, `west update` overwrites ./zephyr/, so we stage a copy of the git-tracked
# files to keep the module.yml intact for ZMK_EXTRA_MODULES.
STAGING_DIR="$SCRIPT_DIR/build/.module-staging"
echo "=== Preparing module staging dir for ZMK_EXTRA_MODULES ==="
rm -rf "$STAGING_DIR"
git -C "$SCRIPT_DIR" checkout-index -a --prefix="$STAGING_DIR/"

echo "=== Building shield=$SHIELD board=$BOARD ${SNIPPET:+snippet=$SNIPPET }==="
echo "=== Build dir: $BUILD_DIR ==="

STUDIO_CMAKE_ARGS=()
if [ -n "$SNIPPET" ]; then
    STUDIO_CMAKE_ARGS+=(-DCONFIG_ZMK_STUDIO=y)
fi

west build -s zmk/app -d "$BUILD_DIR" -b "$BOARD" ${SNIPPET:+-S "$SNIPPET"} -- \
    -DZMK_CONFIG="$SCRIPT_DIR/config" \
    -DSHIELD="$SHIELD" \
    -DZMK_EXTRA_MODULES="$STAGING_DIR" \
    "${STUDIO_CMAKE_ARGS[@]}" \
    "${CMAKE_EXTRA[@]}" \
    2>&1

echo "=== Build complete: $BUILD_DIR/zephyr/zmk.uf2 ==="
