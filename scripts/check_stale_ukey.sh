#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EVIDENCE_ROOT="${OVS_UKEY_EVIDENCE:-$REPO_ROOT/evidence}"

LOG_FILE="$EVIDENCE_ROOT/ovs-vswitchd.log"
COVERAGE_FILE="$EVIDENCE_ROOT/coverage-final.txt"

echo "=== STALE UKEY EVIDENCE CHECK ==="
echo
echo "Evidence root:"
echo "$EVIDENCE_ROOT"

test -f "$LOG_FILE"
test -f "$COVERAGE_FILE"

echo
echo "=== EVIDENCE SUMMARY ==="
printf 'STALE_UKEY_DEBUG records: '
grep -c 'STALE_UKEY_DEBUG' "$LOG_FILE" || true

printf 'Datapath delete failure records: '
grep -ic 'failed to flow_del' "$LOG_FILE" || true

printf 'Coverage records: '
grep -c 'revalidate_missing_dp_flow' "$COVERAGE_FILE" || true

echo
echo "=== ASSERTIONS ==="

for n in 1 2 3 4; do
    grep -q "missed_dumps=$n" "$LOG_FILE"
    echo "PASS: missed_dumps=$n"
done

grep -q "failed to flow_del" "$LOG_FILE"
echo "PASS: datapath delete attempted"

grep -q "No such file or directory" "$LOG_FILE"
echo "PASS: datapath flow already absent"

grep -q "revalidate_missing_dp_flow.*total: [1-9]" "$COVERAGE_FILE"
echo "PASS: revalidate_missing_dp_flow coverage reached"

echo
echo "STALE UKEY EVIDENCE: PASS"
