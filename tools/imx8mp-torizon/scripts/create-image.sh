#!/usr/bin/env bash
set -euo pipefail

# Root is required to preserve guest owners, modes, device nodes and xattrs.
# Internal package builder; use ../prepare.sh on the host.
OUTPUT=artifacts/torizon-emmc.img
while getopts "o:" opt; do
    case "$opt" in
        o) OUTPUT=$OPTARG ;;
        *) exit 2 ;;
    esac
done
shift $((OPTIND - 1))
[[ $# == 1 ]] || { echo "Usage: sudo $0 [-o disk.img] torizon-Tezi.tar" >&2; exit 2; }
[[ $EUID == 0 ]] || { echo "Run as root to preserve guest filesystem ownership." >&2; exit 1; }
for tool in tar xz zstd python3 mkfs.ext4 parted truncate; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done
[[ ! -e $OUTPUT && ! -L $OUTPUT ]] || { echo "Refusing to overwrite $OUTPUT" >&2; exit 1; }
BUNDLE=${OUTPUT%.img}.boot
[[ ! -e $BUNDLE && ! -L $BUNDLE ]] || { echo "Refusing to overwrite $BUNDLE" >&2; exit 1; }
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p -- "$(dirname -- "$OUTPUT")"
STAGING=$(mktemp -d "$(dirname -- "$OUTPUT")/.image.XXXXXXXX")
trap 'rm -rf -- "$STAGING"' EXIT
mkdir "$STAGING/tezi" "$STAGING/rootfs"
tar -xf "$1" -C "$STAGING/tezi"
TEZI_DIR=$(python3 "$ROOT/scripts/stage-tezi.py" "$STAGING/tezi" "$STAGING/rootfs" --output "$STAGING/bundle")
python3 "$ROOT/scripts/inspect-boot.py" "$STAGING/rootfs" --output "$STAGING/bundle"
python3 "$ROOT/scripts/extract-firmware.py" "$TEZI_DIR/imx-boot" --output "$STAGING/bundle"
IDENTITY_ARGS=()
if [[ -n ${RENODE_BOARD_SERIAL:-} ]]; then
    IDENTITY_ARGS=(--serial-number "$RENODE_BOARD_SERIAL")
fi
python3 "$ROOT/scripts/prepare-boot0.py" "$TEZI_DIR" --output "$STAGING/bundle/boot0.img" --extra-args "${RENODE_KERNEL_ARGS:-}" "${IDENTITY_ARGS[@]}"
# Build a fresh disk, with a 1 MiB aligned 2 GiB partition and a 3 GiB device.
# Explicit block size matters: 524288 * 4096 bytes = 2 GiB.
truncate -s 3G "$STAGING/emmc.img"
parted -s "$STAGING/emmc.img" mklabel msdos mkpart primary ext4 1MiB 2049MiB
mkfs.ext4 -q -F -b 4096 -L otaroot -E offset=1048576 \
    -d "$STAGING/rootfs" "$STAGING/emmc.img" 524288
mv -- "$STAGING/emmc.img" "$OUTPUT"
# Keep matching firmware/boot0 beside the disk inside the package.
mv -- "$STAGING/bundle" "$BUNDLE"
echo "Prepared $OUTPUT and $BUNDLE with unmodified U-Boot and BL31."
