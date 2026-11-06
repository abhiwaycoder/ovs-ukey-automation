import hashlib
from pathlib import Path
import sys

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from verify_ovs_package_state import ValidationError, validate_snapshot  # noqa: E402


EXPECTED_NEVRA = "openvswitch2.17-2.17.0-106.el8.x86_64"


def _write_capture(directory: Path, name: str, body: str, exit_code: int = 0):
    content = (
        f"Capture: {name}\n"
        "Label: after-upgrade\n"
        "UTC: 2026-11-06T00:00:00Z\n\n"
        f"{body}\n"
        f"COMMAND_EXIT_CODE={exit_code}\n"
    )
    (directory / f"{name}.txt").write_text(content, encoding="utf-8")


def _snapshot(directory: Path, *, nevra=EXPECTED_NEVRA, ukey_count=0, db_owner="openvswitch:hugetlbfs", db_mode="640"):
    directory.mkdir()
    (directory / "metadata.txt").write_text(
        "Label: after-upgrade\nCaptured UTC: 2026-11-06T00:00:00Z\n"
        "OS: Red Hat Enterprise Linux 8.10\nKernel: 4.18.0-test\n",
        encoding="utf-8",
    )
    _write_capture(directory, "os-release", 'ID="rhel"\nVERSION_ID="8.10"\n')
    _write_capture(directory, "installed-ovs-packages", nevra + "\n")
    _write_capture(
        directory,
        "installed-main-package-signature",
        nevra + "\nSIGPGP=RSA/SHA512, Thu 05 Nov 2026\n",
    )
    _write_capture(directory, "rpm-verify-main-package", "")
    _write_capture(
        directory,
        "service-status",
        "● ovsdb-server.service - OVSDB\n Active: active (running)\n"
        "● ovs-vswitchd.service - OVSD\n Active: active (running)\n",
    )
    _write_capture(directory, "ovs-topology", 'Bridge "br-ukey-runtime"\n')
    _write_capture(
        directory,
        "ovs-database-metadata",
        f"regular file | {db_owner} | mode={db_mode} | size=1234 | /etc/openvswitch/conf.db\n",
    )
    _write_capture(directory, "ovs-binary-checksums", "abc  /usr/bin/ovs-vswitchd\n")
    _write_capture(
        directory,
        "ovs-upcall-state",
        f"flows (current 0)\n6: (keys {ukey_count})\n",
    )

    checksum_lines = []
    for path in sorted(directory.glob("*.txt")):
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        checksum_lines.append(f"{digest}  ./{path.name}")
    (directory / "SHA256SUMS").write_text("\n".join(checksum_lines) + "\n", encoding="utf-8")
    return directory


def test_snapshot_verifier_accepts_valid_rhel810_after_upgrade_snapshot(tmp_path):
    snapshot = _snapshot(tmp_path / "after-upgrade")
    checks = validate_snapshot(
        snapshot,
        expected_nevra=EXPECTED_NEVRA,
        required_bridge="br-ukey-runtime",
        assert_zero_ukeys=True,
    )
    assert any("RHEL 8.10" in check for check in checks)
    assert any("zero" in check.lower() for check in checks)


def test_snapshot_verifier_rejects_checksum_mismatch(tmp_path):
    snapshot = _snapshot(tmp_path / "after-upgrade")
    with (snapshot / "ovs-topology.txt").open("a", encoding="utf-8") as stream:
        stream.write("tampered\n")
    with pytest.raises(ValidationError, match="Checksum mismatch"):
        validate_snapshot(snapshot, expected_nevra=EXPECTED_NEVRA)


def test_snapshot_verifier_rejects_wrong_nevra(tmp_path):
    snapshot = _snapshot(tmp_path / "after-upgrade")
    with pytest.raises(ValidationError, match="Expected package NEVRA"):
        validate_snapshot(
            snapshot,
            expected_nevra="openvswitch2.17-2.17.0-999.el8.x86_64",
        )


def test_snapshot_verifier_rejects_nonzero_final_ukeys(tmp_path):
    snapshot = _snapshot(tmp_path / "after-runtime", ukey_count=2)
    with pytest.raises(ValidationError, match="Expected zero final UKEYs"):
        validate_snapshot(
            snapshot,
            expected_nevra=EXPECTED_NEVRA,
            assert_zero_ukeys=True,
        )


def test_snapshot_verifier_compares_database_owner_and_mode(tmp_path):
    before = _snapshot(tmp_path / "before-upgrade")
    after = _snapshot(
        tmp_path / "after-upgrade",
        db_owner="root:root",
        db_mode="600",
    )
    with pytest.raises(ValidationError, match="conf.db type, ownership, or mode changed"):
        validate_snapshot(
            after,
            expected_nevra=EXPECTED_NEVRA,
            compare_database_with=before,
        )


def test_snapshot_verifier_rejects_rpm_verify_differences(tmp_path):
    snapshot = _snapshot(tmp_path / "after-upgrade")
    _write_capture(
        snapshot,
        "rpm-verify-main-package",
        "S.5....T.  c /etc/openvswitch/conf.db",
    )
    checksum_lines = []
    for path in sorted(snapshot.glob("*.txt")):
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        checksum_lines.append(f"{digest}  ./{path.name}")
    (snapshot / "SHA256SUMS").write_text("\n".join(checksum_lines) + "\n", encoding="utf-8")
    with pytest.raises(ValidationError, match="rpm -V openvswitch2.17 reported"):
        validate_snapshot(snapshot, expected_nevra=EXPECTED_NEVRA)
