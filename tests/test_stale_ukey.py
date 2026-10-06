import os
import re
from collections import defaultdict
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
DEBUG_FILE = EVIDENCE_ROOT / "stale-ukey-debug.log"
COVERAGE_FILE = EVIDENCE_ROOT / "coverage-final.txt"


def read_required(path):
    assert path.is_file(), f"Missing evidence file: {path}"
    return path.read_text(errors="replace")


def test_same_ukey_reaches_four_missed_dumps_in_order():
    log = read_required(LOG_FILE)
    events = re.findall(
        r"STALE_UKEY_DEBUG:\s+ukey=(0x[0-9a-fA-F]+).*?missed_dumps=(\d+)",
        log,
    )
    by_ukey = defaultdict(list)
    for ukey, count in events:
        by_ukey[ukey].append(int(count))

    assert by_ukey, "No parseable STALE_UKEY_DEBUG UKEY events found"
    assert any(
        any(
            counts[i:i + 4] == [1, 2, 3, 4]
            for i in range(len(counts) - 3)
        )
        for counts in by_ukey.values()
    ), f"No single UKEY showed ordered misses 1-4: {dict(by_ukey)}"


def test_stale_ukey_attempts_datapath_delete():
    log = read_required(LOG_FILE)
    assert "missed_dumps=4" in log
    assert "failed to flow_del" in log
    assert "No such file or directory" in log


def test_stale_ukey_coverage_counter():
    coverage = read_required(COVERAGE_FILE)
    match = re.search(
        r"revalidate_missing_dp_flow.*?total:\s*(\d+)",
        coverage,
    )
    assert match, "revalidate_missing_dp_flow coverage counter not found"
    assert int(match.group(1)) >= 1, (
        f"Expected coverage >= 1, got {match.group(1)}"
    )


def test_ovs_evidence_files_exist():
    required = [
        LOG_FILE,
        DEBUG_FILE,
        COVERAGE_FILE,
        EVIDENCE_ROOT / "dp-final.txt",
        EVIDENCE_ROOT / "upcall-final.txt",
    ]
    missing = [str(path) for path in required if not path.is_file()]
    assert not missing, "Missing evidence files:\n" + "\n".join(missing)

    debug = read_required(DEBUG_FILE)
    assert "STALE_UKEY_DEBUG" in debug, "Debug evidence has no UKEY events"
