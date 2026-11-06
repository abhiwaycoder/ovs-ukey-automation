import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
RUNTIME_SCRIPT = REPO_ROOT / "scripts" / "reproduce_stale_ukey.sh"
INSTALLER_SCRIPT = REPO_ROOT / "scripts" / "install_runtime_runner.sh"
ENTRYPOINT_SCRIPT = REPO_ROOT / "scripts" / "ovs-ukey-ci"
CONFIG_EXAMPLE = REPO_ROOT / "config" / "ovs-ukey-ci.conf.example"


def bash_syntax(path: Path):
    return subprocess.run(
        ["bash", "-n", str(path)],
        check=False,
        capture_output=True,
        text=True,
    )


def test_runtime_reproduction_script_has_valid_bash_syntax():
    result = bash_syntax(RUNTIME_SCRIPT)
    assert result.returncode == 0, result.stderr


def test_runner_installer_and_entrypoint_have_valid_bash_syntax():
    for path in (INSTALLER_SCRIPT, ENTRYPOINT_SCRIPT):
        result = bash_syntax(path)
        assert result.returncode == 0, f"{path}: {result.stderr}"


def test_runtime_reproduction_uses_root_owned_config_and_rejects_weak_permissions():
    content = RUNTIME_SCRIPT.read_text(encoding="utf-8")
    assert 'OVS_UKEY_CI_CONFIG_FILE:-/etc/ovs-ukey-ci.conf' in content
    assert 'stat -c \'%u\' "$CONFIG_FILE"' in content
    assert 'stat -c \'%a\' "$CONFIG_FILE"' in content
    assert 'source "$CONFIG_FILE"' in content
    assert '8#$config_mode & 0022' in content
    assert '[[ "$EUID" -eq 0 ]]' in content


def test_runtime_paths_are_configurable_and_pid_database_checks_use_them():
    content = RUNTIME_SCRIPT.read_text(encoding="utf-8")
    for setting in (
        "OVS_UKEY_RUNTIME_ROOT",
        "OVS_UKEY_SOURCE_ROOT",
        "OVS_UKEY_DB_SOCKET",
        "OVS_UKEY_PID_FILE",
        "OVS_UKEY_LIBOFPROTO",
        "OVS_UKEY_EVIDENCE",
        "OVS_UKEY_RUNNER_GROUP",
    ):
        assert setting in content
    assert 'cat "$OVS_PID_FILE"' in content
    assert 'grep -Fq "$DB_SOCKET"' in content
    assert 'chgrp -R "$RUNNER_GROUP" "$EVIDENCE"' in content
    assert 'LIB="/root/ovs-3.5.3/ofproto/.libs/libofproto-3.5.so.0.0.3"' not in content


def test_runner_installer_grants_only_the_fixed_reproduction_command():
    content = INSTALLER_SCRIPT.read_text(encoding="utf-8")
    assert 'EXPECTED_RULE="$RUNNER_USER ALL=(root) NOPASSWD: /usr/local/sbin/ovs-ukey-ci"' in content
    assert "visudo -cf" in content
    assert "unexpected_rules" in content
    assert "NOPASSWD: ALL" not in content
    assert "/usr/local/libexec/ovs-ukey-ci/reproduce_stale_ukey.sh" in ENTRYPOINT_SCRIPT.read_text(encoding="utf-8")


def test_runner_configuration_example_uses_expected_evidence_path():
    content = CONFIG_EXAMPLE.read_text(encoding="utf-8")
    assert 'OVS_UKEY_EVIDENCE="/var/lib/ovs-ukey-ci/evidence"' in content
    assert "OVS_UKEY_SOURCE_ROOT" in content
    assert "OVS_UKEY_RUNTIME_ROOT" in content
