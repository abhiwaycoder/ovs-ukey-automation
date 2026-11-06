import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
RELEASE_SCRIPT = REPO_ROOT / "scripts" / "package_signed_ovs_release.sh"


def test_signed_release_helper_has_valid_bash_syntax():
    result = subprocess.run(
        ["bash", "-n", str(RELEASE_SCRIPT)],
        check=False,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr


def test_signed_release_helper_checks_packages_and_repository_signature():
    content = RELEASE_SCRIPT.read_text(encoding="utf-8")
    assert "7F34141A60E9B91DABF3978DFEC22E62BB0AD5CB" in content
    assert "rpmkeys --dbpath" in content
    assert "--checksig --verbose" in content
    assert "repomd.xml.asc" in content
    assert "gpg --homedir" in content
    assert "Expected exactly 9 signed binary RPMs" in content
    assert "Expected exactly 1 signed source RPM" in content


def test_signed_release_helper_only_creates_a_draft_release():
    content = RELEASE_SCRIPT.read_text(encoding="utf-8")
    assert "--create-draft" in content
    assert "gh release create" in content
    assert "--draft" in content
    release_command = content.split("gh release create", 1)[1]
    assert "--draft" in release_command
