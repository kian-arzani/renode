#!/usr/bin/env python3
"""Generate U-Boot commands from an installed OSTree boot entry."""
import argparse
import hashlib
import json
from pathlib import Path
import re


def prepare(rootfs, output, dtb, extra_args="", bootloader_entropy=False, manifest_only=False):
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
    args = "console=ttymxc2,115200 earlycon root=LABEL=otaroot rootfstype=ext4 rootwait rw "
    args += entry["options"] + " " + extra_args
    if any(c in args for c in "\r\n;'\""):
        raise ValueError("Boot arguments contain U-Boot command syntax")
    commands = [
        "setenv kernel_comp_addr_r 0x58000000",
        "setenv kernel_comp_size 0x4000000",
        "setenv bootargs " + args.strip(),
        "setenv renode_kernel 'ext4load mmc 2:1 0x50000000 " + paths["kernel"] + "'",
        "setenv renode_dtb 'ext4load mmc 2:1 0x52000000 " + paths["dtb"] + "'",
        "setenv renode_initramfs 'ext4load mmc 2:1 0x53000000 " + paths["initramfs"] + "'",
        "mmc dev 2 && run renode_kernel && run renode_dtb && run renode_initramfs && "
        "booti 0x50000000 0x53000000:${filesize} 0x52000000",
    ]
    if bootloader_entropy:
        # Bytes are supplied freshly in RAM by the launch harness, never stored
        # in the disk, command file, environment image or UART logs.
        seed_command = (
            "itest.l *0x57000040 == 0x524e4753 && fdt addr 0x52000000 && fdt resize 0x1000 && fdt set /chosen rng-seed ["
            + " ".join(["00"] * 64)
            + "] && fdt get addr renode_seed_addr /chosen rng-seed"
            " && cp.b 0x57000000 ${renode_seed_addr} 0x40"
            " && mw.b 0x57000000 0 0x44 && setenv renode_seed_addr")
        commands.insert(-1, "setenv renode_seed '" + seed_command + "'")
        commands[-1] = commands[-1].replace(" && booti ", " && run renode_seed && booti ")
    if any(len(cmd) > 1000 for cmd in commands):
        raise ValueError("U-Boot command exceeds its console buffer")
    output.mkdir(parents=True, exist_ok=True)
    if not manifest_only:
        (output / "boot-commands.txt").write_text("\n".join(commands) + "\n")
    (output / "boot-manifest.json").write_text(json.dumps({
        "entry": str(entries[0].relative_to(rootfs)), "paths": paths,
        "sha256": hashes, "bootargs": args.strip(),
        "bootloader_entropy": bootloader_entropy,
    }, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rootfs", type=Path)
    parser.add_argument("--output", type=Path, default=Path("artifacts"))
    parser.add_argument("--dtb", default="imx8mp-verdin-wifi-dev.dtb")
    parser.add_argument("--extra-args", default="")
    parser.add_argument("--manifest-only", action="store_true", help="Record OS paths/hashes without legacy console commands")
    parser.add_argument("--bootloader-entropy", action="store_true",
                        help="Pass fresh launch-harness entropy via /chosen/rng-seed")
    options = parser.parse_args()
    try:
        prepare(options.rootfs, options.output, options.dtb, options.extra_args, options.bootloader_entropy, options.manifest_only)
    except (ValueError, KeyError, OSError) as error:
        parser.exit(1, f"prepare-boot: {error}\n")
