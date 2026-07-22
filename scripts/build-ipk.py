#!/usr/bin/env python3
"""Build a small, deterministic OpenWrt IPK without an OpenWrt SDK."""

from __future__ import annotations

import argparse
import gzip
import io
import tarfile
from pathlib import Path


PACKAGE = "luci-app-passwall-snell"
VERSION = "1.0.3-1"
ARCHITECTURE = "all"


def tar_gz_from_bytes(files: list[tuple[str, bytes, int]]) -> bytes:
    output = io.BytesIO()
    with gzip.GzipFile(fileobj=output, mode="wb", filename="", mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode="w", format=tarfile.GNU_FORMAT) as archive:
            for archive_name, data, mode in files:
                info = tarfile.TarInfo(name=f"./{archive_name}")
                info.size = len(data)
                info.mode = mode
                info.uid = 0
                info.gid = 0
                info.uname = "root"
                info.gname = "root"
                info.mtime = 0
                archive.addfile(info, io.BytesIO(data))
    return output.getvalue()


def tar_gz_from_files(root: Path, files: list[tuple[str, Path, int]]) -> bytes:
    return tar_gz_from_bytes([
        (archive_name, source.read_bytes(), mode)
        for archive_name, source, mode in files
    ])


def build_control(root: Path) -> bytes:
    control_root = root / "packaging"
    files = [
        ("control", control_root / "control", 0o644),
        ("conffiles", control_root / "conffiles", 0o644),
        ("postinst", control_root / "postinst", 0o755),
        ("prerm", control_root / "prerm", 0o755),
        ("postrm", control_root / "postrm", 0o755),
    ]
    return tar_gz_from_files(root, files)


def data_mode(path: Path) -> int:
    normalized = path.as_posix()
    if normalized.endswith("/etc/init.d/passwall-snell"):
        return 0o755
    if normalized.endswith((
        "/usr/share/passwall-snell/launcher.sh",
        "/usr/share/passwall-snell/migrate-config.sh",
    )):
        return 0o755
    if normalized.endswith("/etc/config/passwall_snell"):
        return 0o600
    return 0o644


def build_data(root: Path) -> bytes:
    data_root = root / "files"
    files: list[tuple[str, Path, int]] = []
    for source in sorted(data_root.rglob("*")):
        if source.is_file():
            relative = source.relative_to(data_root).as_posix()
            files.append((relative, source, data_mode(relative_path(relative))))
    return tar_gz_from_files(root, files)


def relative_path(value: str) -> Path:
    return Path("files") / Path(value)


def build_ipk(root: Path, output: Path) -> None:
    control = build_control(root)
    data = build_data(root)
    package = tar_gz_from_bytes([
        ("debian-binary", b"2.0\n", 0o644),
        ("data.tar.gz", data, 0o644),
        ("control.tar.gz", control, 0o644),
    ])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(package)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path("dist"))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output_dir = args.output if args.output.is_absolute() else root / args.output
    output = output_dir / f"{PACKAGE}_{VERSION}_{ARCHITECTURE}.ipk"
    build_ipk(root, output)
    print(output)


if __name__ == "__main__":
    main()
