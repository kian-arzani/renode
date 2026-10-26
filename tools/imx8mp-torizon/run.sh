#!/usr/bin/env bash
set -euo pipefail
TOOLS=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(cd -- "$TOOLS/../.." && pwd)
[[ $# == 1 ]] || { echo "Usage: $0 PACKAGE_DIR" >&2; exit 2; }
PACKAGE=$(realpath -e -- "$1")
[[ $PACKAGE =~ ^/[A-Za-z0-9_./+-]+$ ]] || { echo "Package path must not contain spaces or monitor metacharacters." >&2; exit 2; }
INPUTS=$(python3 "$TOOLS/scripts/package.py" resolve "$PACKAGE")
mapfile -t FILES <<< "$INPUTS"
cd -- "$ROOT"
exec ./renode --console --disable-gui \
    -e "\$emmc_image=@${FILES[0]/#\/package/$PACKAGE}" \
    -e "\$boot0_image=@${FILES[1]/#\/package/$PACKAGE}" \
    -e "\$uboot_binary=@${FILES[2]/#\/package/$PACKAGE}" \
    -e "\$bl31_binary=@${FILES[3]/#\/package/$PACKAGE}" \
    -e 'include @scripts/single-node/toradex-verdin-imx8mp-torizon.resc' \
    -e 'logLevel 3' \
    -e 'emulation CreateServerSocketTerminal 12345 "linux-console"' \
    -e 'connector Connect sysbus.uart3 linux-console' -e start
