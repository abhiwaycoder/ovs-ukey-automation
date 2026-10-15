#!/usr/bin/env bash
set -uo pipefail

WORK_DIR="${WORK_DIR:-/root/ovs-upstream-review}"
BASELINE="${BASELINE_TREE:-$WORK_DIR/baseline-test}"
PATCHED="${PATCHED_TREE:-$WORK_DIR/patched}"
FIX="${FIX_COMMIT:-ce789d991f748d95a34355e7813ddf18a64de504}"
TEST_ID="${TEST_ID:-1315}"

usage() {
    echo "Usage: $0 [--work-dir DIR] [--baseline DIR] [--patched DIR]"
    echo "          [--fix-commit SHA] [--test-id ID]"
}

while (($#)); do
    case "$1" in
        --work-dir)   WORK_DIR="$2"; shift 2 ;;
        --baseline)   BASELINE="$2"; shift 2 ;;
        --patched)    PATCHED="$2"; shift 2 ;;
        --fix-commit) FIX="$2"; shift 2 ;;
        --test-id)    TEST_ID="$2"; shift 2 ;;
        -h|--help)    usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

for tree in "$BASELINE" "$PATCHED"; do
    if [[ ! -x "$tree/tests/testsuite" ]]; then
        echo "ERROR: missing test harness: $tree/tests/testsuite" >&2
        exit 2
    fi
done

base_head=$(git -C "$BASELINE" rev-parse HEAD) || exit 2
patched_head=$(git -C "$PATCHED" rev-parse HEAD) || exit 2
parent=$(git -C "$PATCHED" rev-parse "$FIX^") || exit 2

if [[ "$base_head" != "$parent" || "$patched_head" != "$FIX" ]]; then
    echo "ERROR: baseline/fix commit relationship does not match."
    echo "Baseline: $base_head"
    echo "Fix parent: $parent"
    echo "Patched: $patched_head"
    echo "Expected fix: $FIX"
    exit 2
fi

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
EVIDENCE="$WORK_DIR/evidence-$STAMP"
mkdir -p "$EVIDENCE" || exit 2
exec > >(tee "$EVIDENCE/automation.log") 2>&1

echo "OVS_STALE_UKEY_VALIDATION"
echo "UTC_START=$(date -u +%FT%TZ)"
echo "FIX_COMMIT=$FIX"
echo "BASELINE_HEAD=$base_head"
echo "PATCHED_HEAD=$patched_head"
echo "EVIDENCE_DIR=$EVIDENCE"

run_test() {
    local label="$1" tree="$2" rc=0
    local log="$EVIDENCE/$label.log"

    echo "===== RUN $label ====="
    (
        cd "$tree/tests" &&
        timeout 180 ./testsuite \
            AUTOTEST_PATH="$tree/ovsdb:$tree/vswitchd:$tree/utilities:$tree/tests" \
            --verbose "$TEST_ID"
    ) >"$log" 2>&1 || rc=$?

    echo "$rc" > "$EVIDENCE/$label.exit-code"
    echo "${label^^}_EXIT_CODE=$rc"
    grep -E 'Cleanup missing datapath flows|FAILED|test was successful|ERROR' \
        "$log" | tail -n 12 || true
}

run_test baseline "$BASELINE"
run_test patched "$PATCHED"

base_rc=$(cat "$EVIDENCE/baseline.exit-code")
patched_rc=$(cat "$EVIDENCE/patched.exit-code")

if [[ "$base_rc" -ne 0 && "$patched_rc" -eq 0 ]] &&
   grep -q 'Cleanup missing datapath flows' "$EVIDENCE/baseline.log" &&
   grep -q 'FAILED' "$EVIDENCE/baseline.log" &&
   grep -q '1 test was successful' "$EVIDENCE/patched.log"; then
    result=PASS
else
    result=FAIL
fi

{
    echo "OVS stale-ukey automated comparison"
    echo "UTC_FINISH=$(date -u +%FT%TZ)"
    echo "FIX_COMMIT=$FIX"
    echo "BASELINE_HEAD=$base_head"
    echo "PATCHED_HEAD=$patched_head"
    echo "BASELINE_EXIT_CODE=$base_rc"
    echo "PATCHED_EXIT_CODE=$patched_rc"
    echo "RESULT=$result"
    echo "BASELINE_LOG=$EVIDENCE/baseline.log"
    echo "PATCHED_LOG=$EVIDENCE/patched.log"
} > "$EVIDENCE/summary.txt"

sha256sum "$EVIDENCE/baseline.log" "$EVIDENCE/patched.log" \
    "$EVIDENCE/summary.txt" > "$EVIDENCE/SHA256SUMS"

cat "$EVIDENCE/summary.txt"
echo "CHECKSUMS=$EVIDENCE/SHA256SUMS"
echo "EVIDENCE_DIR=$EVIDENCE"

[[ "$result" == PASS ]]
