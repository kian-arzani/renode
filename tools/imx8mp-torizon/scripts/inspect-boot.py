#!/usr/bin/env python3
"""Inspect OS boot paths without generating a replacement boot sequence."""
import argparse
import hashlib
import json
from pathlib import Path
import re


def inspect(rootfs, output, dtb):
    entries = sorted((rootfs / "boot/loader/entries").glob("*.conf"))
    if len(entries) != 1:
        raise ValueError(f"Expected one active OSTree boot entry, found {len(entries)}")
    entry = dict(line.split(None, 1) for line in entries[0].read_text().splitlines()
                 if line.strip() and not line.startswith("#"))
    paths = {"kernel": "/boot" + entry["linux"],
             "initramfs": "/boot" + entry["initrd"],
             "dtb": "/boot" + entry["fdtdir"] + "/" + dtb}
    hashes = {}
    for name, path in paths.items():
        if not re.fullmatch(r"/[A-Za-z0-9_./+\-]+", path) or ".." in path.split("/"):
            raise ValueError(f"Unsafe boot path: {path}")
        image = rootfs / path.lstrip("/")
        if not image.is_file():
            raise ValueError(f"Missing {name}: {image}")
        hashes[name] = hashlib.sha256(image.read_bytes()).hexdigest()
    output.mkdir(parents=True, exist_ok=True)
    (output / "boot-manifest.json").write_text(json.dumps({
        "entry": str(entries[0].relative_to(rootfs)), "paths": paths,
        "sha256": hashes, "bootargs_source": "supplied distro/OSTree boot script and boot0 environment",
    }, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rootfs", type=Path)
    parser.add_argument("--output", type=Path, default=Path("artifacts"))
    parser.add_argument("--dtb", default="imx8mp-verdin-wifi-dev.dtb")
    options = parser.parse_args()
    try:
        inspect(options.rootfs, options.output, options.dtb)
    except (ValueError, KeyError, OSError) as error:
        parser.exit(1, f"inspect-boot: {error}\n")
