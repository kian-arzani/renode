#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")" && pwd)
[[ $# == 3 && $2 == -o ]] || { echo "Usage: $0 IMAGE.tar -o PACKAGE_DIR" >&2; exit 2; }
ARCHIVE=$(realpath -e -- "$1")
OUTPUT=$(realpath -m -- "$3")
[[ -f $ARCHIVE && ! -e $OUTPUT && ! -L $OUTPUT ]] || {
    echo "Input must be a file; output must not exist." >&2; exit 1;
}
mkdir -p -- "$(dirname -- "$OUTPUT")"
cd -- "$ROOT"
docker build -t renode-imx8mp-image-builder - < Dockerfile.image
docker run --rm \
    -e RENODE_BOARD_SERIAL="${RENODE_BOARD_SERIAL:-}" \
    -e RENODE_KERNEL_ARGS="${RENODE_KERNEL_ARGS:-}" \
    -e "PACKAGE_UID=$(id -u)" -e "PACKAGE_GID=$(id -g)" \
    -v "$ROOT:/work:ro" -v "$ARCHIVE:/input/image.tar:ro" \
    -v "$(dirname -- "$OUTPUT"):/output" \
    --entrypoint python3 renode-imx8mp-image-builder \
    /work/scripts/package.py prepare /input/image.tar "/output/$(basename -- "$OUTPUT")"
echo "Ready: ./run.sh '$OUTPUT'"
