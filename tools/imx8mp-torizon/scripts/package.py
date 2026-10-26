#!/usr/bin/env python3
"""Build and validate a self-contained, versioned Renode boot package."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def sha256(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def write_manifest(package):
    firmware = package / 'emmc.boot'
    extraction = json.loads((firmware / 'firmware-manifest.json').read_text())
    for role, name in (('atf', 'bl31.bin'), ('uboot', 'u-boot-nodtb.bin'), ('dtb', 'u-boot.dtb')):
        if sha256(firmware / name) != extraction['components'][role]['sha256']:
            raise ValueError(f'{name} differs from the supplied firmware')
    if (firmware / 'u-boot-with-dtb.bin').read_bytes() != (
            (firmware / 'u-boot-nodtb.bin').read_bytes() + (firmware / 'u-boot.dtb').read_bytes()):
        raise ValueError('U-Boot/control DTB concatenation does not match supplied components')
    # The post-SPL compatibility profile is verified for this BL31 only.
    if sha256(firmware / 'bl31.bin') != '22c3d2b0b56503fb283464016a37fd204eedf34015850b60b11549916579143a':
        raise ValueError('Unknown BL31; verify its post-SPL requirements before adding a profile')
    files = dict(emmc='emmc.img', boot0='emmc.boot/boot0.img',
                 uboot='emmc.boot/u-boot-with-dtb.bin', bl31='emmc.boot/bl31.bin')
    manifest = {
        'format': 1, 'profile': 'verdin-imx8mp-post-spl',
        'files': {key: dict(path=name, size=(package / name).stat().st_size,
                            sha256=sha256(package / name)) for key, name in files.items()},
        'firmware': 'unmodified supplied U-Boot, control DTB and BL31',
        'limitations': ['ROM/SPL/DDR training skipped', 'DDR frequency switching rejected by emulator',
                        'deep CPU powerdown rejected after interrupt wait'],
    }
    (package / 'package.json').write_text(json.dumps(manifest, indent=2) + '\n')


def resolve(package):
    package = package.resolve(strict=True)
    manifest = json.loads((package / 'package.json').read_text())
    if manifest.get('format') != 1 or manifest.get('profile') != 'verdin-imx8mp-post-spl':
        raise ValueError('Unsupported boot package format/profile')
    paths = []
    for key in ('emmc', 'boot0', 'uboot', 'bl31'):
        entry = manifest['files'][key]
        relative = Path(entry['path'])
        path = (package / relative).resolve(strict=True)
        if relative.is_absolute() or not path.is_relative_to(package):
            raise ValueError(f'{key} escapes package')
        if any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./+-' for c in str(relative)):
            raise ValueError(f'Unsupported characters in {key} path')
        if path.stat().st_size != entry['size'] or sha256(path) != entry['sha256']:
            raise ValueError(f'{key} failed integrity verification')
        paths.append('/package/' + str(relative))
    return paths


def prepare(archive, output):
    if output.exists() or output.is_symlink():
        raise ValueError('Refusing to overwrite package')
    output.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix='.renode-package-', dir=output.parent))
    try:
        subprocess.run(['/work/scripts/create-image.sh', '-o', str(staging / 'emmc.img'), str(archive)], check=True)
        write_manifest(staging)
        uid, gid = int(os.environ['PACKAGE_UID']), int(os.environ['PACKAGE_GID'])
        for path in staging.rglob('*'):
            os.chown(path, uid, gid)
        os.chown(staging, uid, gid)
        staging.rename(output)
    finally:
        if staging.exists():
            shutil.rmtree(staging)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('prepare', 'resolve'))
    parser.add_argument('path', type=Path)
    parser.add_argument('output', type=Path, nargs='?')
    args = parser.parse_args()
    try:
        if args.action == 'prepare':
            if args.output is None:
                raise ValueError('prepare requires archive and output directory')
            prepare(args.path, args.output)
        else:
            print('\n'.join(resolve(args.path)))
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'boot package: {error}\n')
