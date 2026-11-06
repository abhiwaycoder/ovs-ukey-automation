import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT_SCRIPT = REPO_ROOT / "scripts" / "capture_ovs_package_state.sh"


def test_package_state_capture_helper_has_valid_bash_syntax():
    result = subprocess.run(
        ["bash", "-n", str(SNAPSHOT_SCRIPT)],
        check=False,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr


def test_package_state_capture_helper_has_explicit_safety_gates():
    content = SNAPSHOT_SCRIPT.read_text(encoding="utf-8")
    assert 'OVS_UKEY_DISPOSABLE_TEST_SYSTEM:-' in content
    assert 'VERSION_ID:-}' in content
    assert '== "8.10"' in content
    assert '[[ "$EUID" -eq 0 ]]' in content
    assert '[[ ! -e "$OUT" ]]' in content


def test_package_state_capture_helper_does_not_change_packages_or_services():
    content = SNAPSHOT_SCRIPT.read_text(encoding="utf-8")
    forbidden_commands = (
        "dnf install",
        "dnf remove",
        "rpm -e",
        "rpm -U",
        "systemctl restart",
        "systemctl stop",
    )
    for command in forbidden_commands:
        assert command not in content
