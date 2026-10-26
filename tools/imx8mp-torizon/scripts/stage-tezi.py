#!/usr/bin/env python3
"""Stage the supported Tezi ext4/otaroot layout, including file-list extras.

Run as root inside the image-builder container. Device-side installation hooks
are never run on the host; unknown hooks/layouts are rejected explicitly.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess


def contained(base, name):
    path = (base / name).resolve()
    if not path.is_relative_to(base.resolve()):
        raise ValueError(f"Path escapes staging directory: {name}")
    return path


def unpack(source, destination):
    destination.mkdir(parents=True, exist_ok=True)
    subprocess.run(["tar", "--numeric-owner", "--xattrs", "--xattrs-include=*", "--acls", "-xpf",
                    str(source), "-C", str(destination)], check=True)


def stage(tezi, rootfs, output):
    descriptors = list(tezi.rglob("image.json"))
    if len(descriptors) != 1:
        raise ValueError("Expected exactly one Tezi image.json")
    descriptor = descriptors[0]
    tezi = descriptor.parent.resolve()
    image = json.loads(descriptor.read_text())
    if image.get("config_format") not in (4, 5):
        raise ValueError("Only Tezi configuration formats 4 and 5 are supported")
    if image.get("u_boot_env") != "u-boot-initial-env-sd":
        raise ValueError("Unsupported U-Boot environment filename/profile")
    blocks = {item["name"]: item for item in image["blockdevs"]}
    if len(blocks) != len(image["blockdevs"]) or set(blocks) != {"emmc", "emmc-boot0"}:
        raise ValueError("Expected only emmc and emmc-boot0 devices")
    parts = blocks["emmc"]["partitions"]
    if len(parts) != 1:
        raise ValueError("Only one otaroot partition is supported")
    content = parts[0]["content"]
    if content["filesystem_type"] != "ext4" or content["label"] != "otaroot":
        raise ValueError("Expected an ext4 partition labelled otaroot")
    raw = blocks["emmc-boot0"]["content"]
    if raw.get("filesystem_type") != "raw" or raw.get("rawfiles") != [
            {"filename": "imx-boot", "dd_options": "seek=0"}]:
        raise ValueError("Unsupported boot0 layout")
    # These are the inspected no-op hooks in the supplied evaluation image.
    # Unknown hooks may perform provisioning; silently omitting them loses data.
    no_op_hashes = {
        "9d3c7a9a5e9d1d9e89f4ad924b249a5e3061f5326c5c683dd18a3cc75f0c742e",
        "a22b39ba67059f012c3964439401939238cbea01b166aa3c1268105039e246d7",
    }
    for key in ("prepare_script", "wrapup_script"):
        if key in image:
            hook = contained(tezi, image[key]).read_bytes()
            if hashlib.sha256(hook).hexdigest() not in no_op_hashes:
                raise ValueError(f"Unverified {key}: inspect its provisioning effects before adding support")
    archive = contained(tezi, content["filename"])
    if not archive.name.endswith((".tar.zst", ".tar.xz", ".tar.gz", ".tar")):
        raise ValueError("Unsupported root archive format")
    unpack(archive, rootfs)
    installed = []
    for item in content.get("filelist", []):
        fields = item.split(":")
        if len(fields) > 3 or (len(fields) == 3 and fields[2] not in ("true", "false")):
            raise ValueError(f"Unsupported file-list tuple: {item}")
        source = contained(tezi, fields[0])
        destination = contained(rootfs, fields[1].lstrip("/") if len(fields) > 1 else "")
        if len(fields) == 3 and fields[2] == "true":
            unpack(source, destination)
        else:
            destination.mkdir(parents=True, exist_ok=True)
            target = contained(rootfs, str(destination / source.name))
            shutil.copy2(source, target)
            os.chown(target, 0, 0)
        installed.append({"source": fields[0], "destination": str(destination.relative_to(rootfs.resolve())),
                          "sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                          "unpacked": len(fields) == 3 and fields[2] == "true"})
    output.mkdir(parents=True, exist_ok=True)
    (output / "image-manifest.json").write_text(json.dumps({
        "version": image.get("version"), "root_archive": archive.name,
        "root_archive_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
        "filelist": installed, "installation_hooks": "verified no-ops or absent",
    }, indent=2) + "\n")
    return tezi


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tezi", type=Path)
    parser.add_argument("rootfs", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        directory = stage(args.tezi, args.rootfs, args.output)
        print(directory)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"stage-tezi: {error}\n")
