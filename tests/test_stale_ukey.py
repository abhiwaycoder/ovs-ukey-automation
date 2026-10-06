import os
import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]

EVIDENCE_ROOT = Path(
    os.environ.get(
        "OVS_UKEY_EVIDENCE",
        (
            REPO_ROOT / "tests" / "fixtures" / "evidence"
            if os.environ.get("CI")
            else REPO_ROOT / "evidence"
        ),
    )
)

LOG_FILE = EVIDENCE_ROOT / "ovs-vswitchd.log"
COVERAGE_FILE = EVIDENCE_ROOT / "coverage-final.txt"


def test_stale_ukey_reaches_four_missed_dumps():
    assert LOG_FILE.exists(), f"Missing OVS log: {LOG_FILE}"

    log = LOG_FILE.read_text(errors="replace")

    matches = re.findall(
        r"STALE_UKEY_DEBUG:.*?missed_dumps=(\d+)",
        log,
    )

    counts = [int(value) for value in matches]

    assert 1 in counts, "No missed_dumps=1 event found"
    assert 2 in counts, "No missed_dumps=2 event found"
    assert 3 in counts, "No missed_dumps=3 event found"
    assert 4 in counts, "No missed_dumps=4 event found"

    assert counts.index(1) < counts.index(2)
    assert counts.index(2) < counts.index(3)
    assert counts.index(3) < counts.index(4)


def test_stale_ukey_attempts_datapath_delete():
    assert LOG_FILE.exists(), f"Missing OVS log: {LOG_FILE}"

    log = LOG_FILE.read_text(errors="replace")

    assert "missed_dumps=4" in log
    assert "failed to flow_del" in log
    assert "No such file or directory" in log


def test_stale_ukey_coverage_counter():
    assert COVERAGE_FILE.exists(), (
        f"Missing coverage file: {COVERAGE_FILE}"
    )

    coverage = COVERAGE_FILE.read_text(errors="replace")

    match = re.search(
        r"revalidate_missing_dp_flow.*?total:\s*(\d+)",
        coverage,
    )

    assert match, (
        "revalidate_missing_dp_flow coverage counter not found"
    )

    total = int(match.group(1))

    assert total >= 1, (
        f"Expected coverage >= 1, got {total}"
    )


def test_ovs_evidence_files_exist():
    required = [
        EVIDENCE_ROOT / "ovs-vswitchd.log",
        EVIDENCE_ROOT / "stale-ukey-debug.log",
        EVIDENCE_ROOT / "coverage-final.txt",
        EVIDENCE_ROOT / "dp-final.txt",
        EVIDENCE_ROOT / "upcall-final.txt",
    ]

    missing = [
        str(path)
        for path in required
        if not path.exists()
    ]

    assert not missing, (
        "Missing evidence files:\n" +
        "\n".join(missing)
    )
