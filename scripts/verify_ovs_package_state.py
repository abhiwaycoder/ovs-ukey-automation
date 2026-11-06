#!/usr/bin/env python3
"""Verify a captured OVS package-state snapshot without changing the host."""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from pathlib import Path


REQUIRED_FILES = (
    "metadata.txt",
    "os-release.txt",
    "installed-ovs-packages.txt",
    "installed-main-package-signature.txt",
    "rpm-verify-main-package.txt",
    "service-status.txt",
    "ovs-topology.txt",
    "ovs-database-metadata.txt",
    "ovs-binary-checksums.txt",
)


class ValidationError(Exception):
    pass


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        raise ValidationError(f"Cannot read {path}: {exc}") from exc


def verify_manifest(snapshot: Path) -> list[str]:
    manifest = snapshot / "SHA256SUMS"
    if not manifest.is_file():
        raise ValidationError(f"Missing checksum manifest: {manifest}")

    verified: list[str] = []
    for line_number, line in enumerate(read_text(manifest).splitlines(), start=1):
        if not line.strip():
            continue
        match = re.fullmatch(r"([0-9a-fA-F]{64})  (.+)", line)
        if not match:
            raise ValidationError(
                f"Invalid SHA-256 manifest entry at {manifest}:{line_number}"
            )
        expected, filename = match.groups()
        relative = Path(filename)
        if relative.is_absolute() or len(relative.parts) != 1 or relative.name in ("", ".", ".."):
            raise ValidationError(f"Unsafe manifest path: {filename}")

        target = snapshot / relative
        if not target.is_file():
            raise ValidationError(f"Manifest file is missing: {target}")
        actual = hashlib.sha256(target.read_bytes()).hexdigest()
        if actual.lower() != expected.lower():
            raise ValidationError(
                f"Checksum mismatch for {filename}: expected {expected}, got {actual}"
            )
        verified.append(relative.name)

    if not verified:
        raise ValidationError("Checksum manifest contains no file entries")

    missing = sorted(set(REQUIRED_FILES) - set(verified))
    if missing:
        raise ValidationError("Manifest does not cover required files: " + ", ".join(missing))
    return verified


def capture_body(snapshot: Path, name: str) -> tuple[str, int]:
    path = snapshot / name
    text = read_text(path)
    match = re.search(r"(?m)^COMMAND_EXIT_CODE=(\d+)\s*$", text)
    if not match:
        raise ValidationError(f"{name} has no COMMAND_EXIT_CODE record")
    header, separator, body = text.partition("\n\n")
    if not separator:
        raise ValidationError(f"{name} has no capture header/body separator")
    if not re.search(r"(?m)^Capture:\s+\S+", header):
        raise ValidationError(f"{name} has no capture header")
    if not re.search(r"(?m)^Label:\s+\S+", header):
        raise ValidationError(f"{name} has no evidence label")
    body = body[: match.start() - len(header) - 2].strip()
    return body, int(match.group(1))


def require_command_success(snapshot: Path, name: str) -> str:
    body, exit_code = capture_body(snapshot, name)
    if exit_code != 0:
        raise ValidationError(f"{name} command exited with status {exit_code}")
    return body


def validate_snapshot(
    snapshot: Path,
    expected_nevra: str,
    required_bridge: str | None = None,
    assert_zero_ukeys: bool = False,
    compare_database_with: Path | None = None,
) -> list[str]:
    snapshot = snapshot.resolve(strict=True)
    if not snapshot.is_dir():
        raise ValidationError(f"Snapshot path is not a directory: {snapshot}")

    verified_files = verify_manifest(snapshot)
    checks = [f"SHA-256 manifest verified ({len(verified_files)} files)"]

    os_release = require_command_success(snapshot, "os-release.txt")
    os_fields = {}
    for line in os_release.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            os_fields[key.strip()] = value.strip().strip('"')
    if os_fields.get("ID") != "rhel" or os_fields.get("VERSION_ID") != "8.10":
        raise ValidationError(
            "Snapshot must be from RHEL 8.10; found "
            f"ID={os_fields.get('ID')!r}, VERSION_ID={os_fields.get('VERSION_ID')!r}"
        )
    checks.append("Operating system is RHEL 8.10")

    packages = require_command_success(snapshot, "installed-ovs-packages.txt")
    if expected_nevra not in packages.splitlines():
        raise ValidationError(
            f"Expected package NEVRA {expected_nevra!r} was not found in installed package list"
        )
    checks.append(f"Expected package installed: {expected_nevra}")

    signature = require_command_success(snapshot, "installed-main-package-signature.txt")
    signature_match = re.search(r"(?m)^SIGPGP=(.+)$", signature)
    if not signature_match or signature_match.group(1).strip().lower() in ("", "(none)", "none"):
        raise ValidationError("Installed main OVS package does not report an RPM signature")
    checks.append("Installed main OVS package reports an RPM signature")

    rpm_verify = require_command_success(snapshot, "rpm-verify-main-package.txt")
    if rpm_verify:
        raise ValidationError(
            "rpm -V openvswitch2.17 reported file differences:\n" + rpm_verify
        )
    checks.append("rpm -V reports no package file differences")

    services = require_command_success(snapshot, "service-status.txt")
    active_services = re.findall(r"(?m)^\s*Active:\s+active\b", services)
    if len(active_services) < 2:
        raise ValidationError(
            "Expected at least two active OVS service status records; "
            f"found {len(active_services)}"
        )
    checks.append(f"OVS services active ({len(active_services)} active records)")

    topology = require_command_success(snapshot, "ovs-topology.txt")
    if required_bridge:
        bridge_pattern = re.compile(
            r"(?m)^\s*Bridge\s+[\"']?" + re.escape(required_bridge) + r"[\"']?\s*$"
        )
        if not bridge_pattern.search(topology):
            raise ValidationError(f"Expected OVS bridge {required_bridge!r} was not found")
        checks.append(f"Expected bridge present: {required_bridge}")

    db_metadata = require_command_success(snapshot, "ovs-database-metadata.txt")
    database_line = next(
        (line for line in db_metadata.splitlines() if "/etc/openvswitch/conf.db" in line),
        None,
    )
    if not database_line:
        raise ValidationError("Database metadata does not include /etc/openvswitch/conf.db")
    db_fields = [field.strip() for field in database_line.split("|")]
    if len(db_fields) < 4 or "mode=" not in db_fields[2]:
        raise ValidationError("Could not parse conf.db owner/group/mode metadata")
    checks.append("OVS database metadata captured")

    if compare_database_with is not None:
        previous = compare_database_with.resolve(strict=True)
        if not previous.is_dir():
            raise ValidationError(f"Comparison snapshot is not a directory: {previous}")
        previous_db = require_command_success(previous, "ovs-database-metadata.txt")
        previous_line = next(
            (line for line in previous_db.splitlines() if "/etc/openvswitch/conf.db" in line),
            None,
        )
        if not previous_line:
            raise ValidationError(
                "Comparison snapshot does not include /etc/openvswitch/conf.db"
            )
        previous_fields = [field.strip() for field in previous_line.split("|")]
        if len(previous_fields) < 4:
            raise ValidationError("Could not parse comparison conf.db metadata")
        current_identity = db_fields[:3]
        previous_identity = previous_fields[:3]
        if current_identity != previous_identity:
            raise ValidationError(
                "conf.db type, ownership, or mode changed: "
                f"before={previous_identity!r}, after={current_identity!r}"
            )
        checks.append("conf.db type, ownership, and mode preserved")

    binary_state = require_command_success(snapshot, "ovs-binary-checksums.txt")
    required_binaries = ("ovs-vswitchd", "ovsdb-server", "ovs-vsctl", "ovs-appctl")
    missing_binaries = [
        name for name in required_binaries
        if f"{name} -> " not in binary_state
    ]
    if missing_binaries:
        raise ValidationError(
            "OVS executable checksum capture is missing: "
            + ", ".join(missing_binaries)
        )
    checks.append("Checksums captured for all four OVS executables")

    if assert_zero_ukeys:
        upcall = require_command_success(snapshot, "ovs-upcall-state.txt")
        counts = re.findall(r"\(keys\s+(\d+)\)", upcall)
        if not counts:
            raise ValidationError("Final OVS upcall state contains no parseable UKEY counts")
        nonzero = [int(count) for count in counts if int(count) != 0]
        if nonzero:
            raise ValidationError(f"Expected zero final UKEYs; found counts {nonzero!r}")
        checks.append("All reported final UKEY counts are zero")

    return checks


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Verify one captured RHEL 8.10 OVS package-state snapshot. "
            "This tool is read-only and does not install or restart packages/services."
        )
    )
    parser.add_argument("--snapshot", required=True, type=Path, help="Snapshot directory to verify")
    parser.add_argument(
        "--expected-nevra",
        required=True,
        help="Exact installed main OVS package NEVRA, for example openvswitch2.17-2.17.0-106.el8.x86_64",
    )
    parser.add_argument(
        "--require-bridge",
        help="Require this bridge name in ovs-vsctl show output",
    )
    parser.add_argument(
        "--assert-zero-ukeys",
        action="store_true",
        help="Require every UKEY count in the final upcall capture to be zero",
    )
    parser.add_argument(
        "--compare-database-with",
        type=Path,
        help="Compare conf.db type, ownership, and mode against an earlier snapshot",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        checks = validate_snapshot(
            snapshot=args.snapshot,
            expected_nevra=args.expected_nevra,
            required_bridge=args.require_bridge,
            assert_zero_ukeys=args.assert_zero_ukeys,
            compare_database_with=args.compare_database_with,
        )
    except (ValidationError, OSError) as exc:
        print(f"VALIDATION FAILED: {exc}", file=sys.stderr)
        return 1

    print("OVS PACKAGE-STATE VALIDATION: PASS")
    for check in checks:
        print(f"PASS: {check}")
    print(f"Snapshot: {args.snapshot.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
