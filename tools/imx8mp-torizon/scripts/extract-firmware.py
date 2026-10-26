#!/usr/bin/env python3
"""Extract unmodified ARM64 U-Boot/ATF components from an i.MX8MP imx-boot FIT.

This prepares a post-SPL handoff, not a ROM/SPL boot image. It does not patch
firmware or establish that the extracted ATF can run in the current platform.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct


def read_fdt(data, start):
    """Read node properties; all offsets and lengths stay within the FDT."""
    if start + 40 > len(data):
        raise ValueError("Truncated FDT header")
    magic, total, off_struct, off_strings, _, version, compatible, _, strings_size, struct_size = struct.unpack_from(
        ">10I", data, start)
    if magic != 0xD00DFEED or version < 17 or compatible > 17:
        raise ValueError("Unsupported FDT header")
    blob = data[start:start + total]
    if len(blob) != total or off_struct + struct_size > total or off_strings + strings_size > total:
        raise ValueError("FDT section exceeds image")
    strings = blob[off_strings:off_strings + strings_size]
    pos, limit, stack, nodes = off_struct, off_struct + struct_size, [], {}
    while pos + 4 <= limit:
        token = struct.unpack_from(">I", blob, pos)[0]
        pos += 4
        if token == 1:
            end = blob.find(b"\0", pos, limit)
            if end < 0:
                raise ValueError("Unterminated node name")
            stack.append(blob[pos:end].decode("ascii"))
            pos = (end + 4) & ~3
            nodes["/" + "/".join(stack[1:])] = {}
        elif token == 2:
            if not stack:
                raise ValueError("Unbalanced FDT nodes")
            stack.pop()
        elif token == 3:
            if not stack or pos + 8 > limit:
                raise ValueError("Invalid FDT property")
            size, name_offset = struct.unpack_from(">II", blob, pos)
            pos += 8
            end = strings.find(b"\0", name_offset)
            if end < 0 or pos + size > limit:
                raise ValueError("Invalid FDT property bounds")
            name = strings[name_offset:end].decode("ascii")
            nodes["/" + "/".join(stack[1:])][name] = blob[pos:pos + size]
            pos = (pos + size + 3) & ~3
        elif token == 4:
            pass
        elif token == 9:
            if stack:
                raise ValueError("Unbalanced FDT end")
            return nodes, total
        else:
            raise ValueError("Unknown FDT token")
    raise ValueError("Missing FDT end")


def string(value):
    return value.rstrip(b"\0").decode("ascii")


def number(value):
    if len(value) not in (4, 8):
        raise ValueError("Expected a 32-bit or 64-bit FIT integer")
    return int.from_bytes(value, "big")


def extract(source, output, configuration=None):
    data = source.read_bytes()
    candidates, pos = [], 0
    while (pos := data.find(b"\xd0\x0d\xfe\xed", pos)) >= 0:
        try:
            nodes, total = read_fdt(data, pos)
            if "/images" in nodes and "/configurations" in nodes:
                candidates.append((pos, nodes, total))
        except (ValueError, UnicodeDecodeError, struct.error):
            pass
        pos += 4
    if len(candidates) != 1:
        raise ValueError(f"Expected one FIT, found {len(candidates)}")
    base, nodes, total = candidates[0]
    config = configuration or string(nodes["/configurations"]["default"])
    selected = nodes["/configurations/" + config]
    firmware = string(selected["firmware"])
    loadables = string(selected["loadables"]).split("\0")
    if len(loadables) != 1:
        raise ValueError("Only a single ATF loadable is supported")
    names = {"uboot": firmware, "atf": loadables[0], "dtb": string(selected["fdt"])}
    components, blobs = {}, {}
    for role, name in names.items():
        props = nodes["/images/" + name]
        if string(props.get("compression", b"none")) != "none":
            raise ValueError(f"Compressed FIT component unsupported: {name}")
        if role != "dtb" and string(props["arch"]) != "arm64":
            raise ValueError(f"Expected ARM64 component: {name}")
        if "data" in props:
            payload = props["data"]
        else:
            size = number(props["data-size"])
            if "data-position" in props:
                offset = base + number(props["data-position"])
            else:
                offset = base + ((total + 3) & ~3) + number(props["data-offset"])
            if offset + size > len(data):
                raise ValueError(f"Truncated FIT payload: {name}")
            payload = data[offset:offset + size]
        if not payload:
            raise ValueError(f"Empty FIT component: {name}")
        blobs[role] = payload
        components[role] = {"fit_name": name, "size": len(payload),
                            "sha256": hashlib.sha256(payload).hexdigest()}
        for key in ("load", "entry"):
            if key in props:
                components[role][key] = number(props[key])
    if components["uboot"]["load"] != 0x40200000 or components["atf"]["load"] != 0x970000:
        raise ValueError("Firmware load addresses do not match the supported i.MX8MP handoff")
    dtb_nodes, _ = read_fdt(blobs["dtb"], 0)
    compatible = string(dtb_nodes["/"]["compatible"]).split("\0")
    if not any("verdin-imx8mp" in value for value in compatible):
        raise ValueError("Expected a Verdin i.MX8MP control DTB")
    # U-Boot's relocation header describes the end of its binary. Its control
    # DTB must be appended there, just as by SPL's FIT loader.
    if len(blobs["uboot"]) < 0x18 or struct.unpack_from("<Q", blobs["uboot"], 0x10)[0] != len(blobs["uboot"]):
        raise ValueError("U-Boot end offset does not match binary size; cannot append DTB safely")
    outputs = {"u-boot-nodtb.bin": blobs["uboot"], "u-boot.dtb": blobs["dtb"],
               "u-boot-with-dtb.bin": blobs["uboot"] + blobs["dtb"], "bl31.bin": blobs["atf"]}
    manifest = {"source": source.name, "source_sha256": hashlib.sha256(data).hexdigest(),
                "fit_offset": base, "configuration": config, "compatible": compatible,
                "components": components, "handoff": "post-SPL; ROM/SPL not executed"}
    outputs["firmware-manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode()
    output.mkdir(parents=True, exist_ok=True)
    if any((output / name).exists() for name in outputs):
        raise ValueError("Output components already exist; choose an empty output directory")
    for name, payload in outputs.items():
        (output / name).write_bytes(payload)
    print(f"Extracted {config} at FIT offset {base:#x} into {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("imx_boot", type=Path)
    parser.add_argument("--output", type=Path, default=Path("artifacts/firmware"))
    parser.add_argument("--configuration")
    args = parser.parse_args()
    try:
        extract(args.imx_boot, args.output, args.configuration)
    except (ValueError, KeyError, OSError, UnicodeDecodeError, struct.error) as error:
        parser.exit(1, f"extract-firmware: {error}\n")
