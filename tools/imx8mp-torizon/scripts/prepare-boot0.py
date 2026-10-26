#!/usr/bin/env python3
"""Prepare an 8 MiB emulated boot0 with the supplied firmware and environment.

The environment layout is specific to Verdin i.MX8MP U-Boot 2024.07: one
8 KiB CRC32 environment at -0x2200, followed by the 512-byte config block.
The optional serial is an explicit virtual identity, not a Toradex config block.
"""
import argparse
import json
from pathlib import Path
import re
import struct
import uuid
import zlib


def prepare(tezi, output, extra_args="", bootloader_entropy=True, serial_number=None):
    if output.exists():
        raise ValueError("Refusing to overwrite boot0")
    if any(c in extra_args for c in "\x00\r\n;'\""):
        raise ValueError("Invalid extra kernel arguments")
    serial_number = serial_number if serial_number is not None else "renode-" + uuid.uuid4().hex[:12]
    if (len(serial_number) > 48
            or not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]*[a-z0-9])?", serial_number)):
        raise ValueError("Serial must be 1–48 lowercase letters, digits or internal hyphens")
    size, env_size, env_offset = 8 * 1024 * 1024, 0x2000, -0x2200
    firmware = (tezi / "imx-boot").read_bytes()
    if b"2024.07-7.7.0+git.3f772959501c" not in firmware:
        raise ValueError("Unknown firmware version; verify its environment layout before adding a profile")
    if len(firmware) > size + env_offset:
        raise ValueError("Firmware overlaps the environment")
    env = {}
    for line in (tezi / "u-boot-initial-env-sd").read_text().splitlines():
        if line and not line.startswith("#"):
            key, value = line.split("=", 1)
            env[key] = value
    # Supply the board selection normally obtained from the hardware's Toradex
    # config block. Keep the supplied distro boot and OSTree script unchanged.
    changes = {"fdtfile": "imx8mp-verdin-wifi-dev.dtb", "boot_targets": "mmc2",
               "defargs": "console=ttymxc2,115200 earlycon", "tdxargs": extra_args,
               "serial#": serial_number}
    env.update(changes)
    payload = b"\0".join(f"{k}={v}".encode() for k, v in env.items()) + b"\0\0"
    if len(payload) > env_size - 4:
        raise ValueError("Environment exceeds 8 KiB")
    payload = payload.ljust(env_size - 4, b"\0")
    boot0 = bytearray(size)
    boot0[:len(firmware)] = firmware
    offset = size + env_offset
    boot0[offset:offset + env_size] = struct.pack("<I", zlib.crc32(payload)) + payload
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(boot0)
    output.with_suffix(output.suffix + ".json").write_text(json.dumps({
        "profile": "Verdin i.MX8MP U-Boot 2024.07 development boot0",
        "environment_offset": offset, "environment_size": env_size,
        "environment_overrides": changes, "config_block": "absent",
        "bootloader_entropy": "automatic-linux-handoff",
        "board_identity": {"serial_number": serial_number, "kind": "emulated", "config_block": "absent"},
    }, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tezi_directory", type=Path)
    parser.add_argument("--output", type=Path, default=Path("artifacts/firmware/boot0.img"))
    parser.add_argument("--extra-args", default="")
    parser.add_argument("--serial-number", help="Stable virtual serial; default: a new renode-<random> identity")
    parser.add_argument("--bootloader-entropy", action="store_true",
                        help="Compatibility option; native entropy is supplied by the automatic Renode handoff")
    args = parser.parse_args()
    try:
        prepare(args.tezi_directory, args.output, args.extra_args, args.bootloader_entropy, args.serial_number)
    except (ValueError, OSError) as error:
        parser.exit(1, f"prepare-boot0: {error}\n")
