#!/bin/bash
set -euo pipefail

R=/root/ovs-debug-runtime3
NS=ovs-ukey-ns
BR=ukey-br
OVS_VSCTL=/root/ovs-3.5.3/utilities/ovs-vsctl
DB=unix:$R/run/db.sock
APP=/root/ovs-3.5.3/utilities/ovs-appctl
OVS_VSWITCHD=/root/ovs-3.5.3/vswitchd/ovs-vswitchd

CTL="$R/run/ovs-vswitchd.ctl"
LOG="$R/logs/ovs-vswitchd.log"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
EVIDENCE="$REPO/evidence"

export LD_LIBRARY_PATH="/root/ovs-3.5.3/ofproto/.libs:/root/ovs-3.5.3/lib/.libs"

mkdir -p "$EVIDENCE"
mkdir -p /usr/local/var/run/openvswitch

echo "=================================================="
echo "1. VERIFY INSTRUMENTED OVS"
echo "=================================================="

"$OVS_VSWITCHD" --version | head -1

LIB="/root/ovs-3.5.3/ofproto/.libs/libofproto-3.5.so.0.0.3"

if [ ! -f "$LIB" ]; then
    echo "FAIL: instrumented libofproto not found: $LIB"
    exit 1
fi

if grep -a -q 'STALE_UKEY_DEBUG' "$LIB"; then
    echo "PASS: instrumented libofproto found"
else
    echo "FAIL: STALE_UKEY_DEBUG not found in libofproto"
    exit 1
fi

echo
echo "=================================================="
echo "2. VERIFY DISPOSABLE RUNTIME"
echo "=================================================="

if [ ! -S "$CTL" ]; then
    echo "FAIL: OVS control socket missing: $CTL"
    exit 1
fi

if ! ip netns list | grep -q "^${NS}[[:space:]]"; then
    echo "FAIL: network namespace missing: $NS"
    exit 1
fi

if ! ip netns exec "$NS" "$APP" -t "$CTL" version; then
    echo "FAIL: cannot contact disposable ovs-vswitchd"
    exit 1
fi

echo "PASS: disposable OVS runtime reachable"

echo
echo "=================================================="
echo "3. PREPARE TEST NETWORK"
echo "=================================================="

VETH="ukey-veth1"
PEER="ukey-peer1"

echo "--- Clean stale test interfaces ---"

# Remove the root-side peer if it was left behind by a previous run.
ip link del "$PEER" 2>/dev/null || true

# Remove the test-side veth if it still exists in the disposable namespace.
ip netns exec "$NS" ip link del "$VETH" 2>/dev/null || true

echo "--- Create fresh veth pair ---"

ip link add "$VETH" type veth peer name "$PEER"

# Keep the peer in the root namespace and move the OVS-facing side
# into the disposable namespace.
ip link set "$VETH" netns "$NS"

echo "--- Bring interfaces up ---"

ip link set "$PEER" up
ip netns exec "$NS" ip link set "$VETH" up
ip netns exec "$NS" ip link set ukey-br up

echo "--- Ensure veth is attached to disposable OVS bridge ---"

if ! "$OVS_VSCTL" --db="$DB" list-ports "$BR" | grep -qx "$VETH"; then
    "$OVS_VSCTL" --db="$DB" --may-exist add-port "$BR" "$VETH"
fi

echo "Bridge:"
ip netns exec "$NS" ip -br link show ukey-br

echo "Veth:"
ip netns exec "$NS" ip -br link show "$VETH"

echo "Peer:"
ip -br link show "$PEER"

echo
echo "=================================================="
echo "4. INITIAL STATE"
echo "=================================================="

ip netns exec "$NS" \
    "$APP" -t "$CTL" upcall/show

ip netns exec "$NS" \
    "$APP" -t "$CTL" dpctl/dump-flows || true

echo
echo "=================================================="
echo "5. GENERATE DETERMINISTIC IPV6 TRAFFIC"
echo "=================================================="

ip netns exec "$NS" \
    ping6 -c 3 -I ukey-veth1 ff02::1 || true

sleep 1

echo
echo "Datapath flows after traffic:"
ip netns exec "$NS" \
    "$APP" -t "$CTL" dpctl/dump-flows || true

echo
echo "UKEY state after traffic:"
ip netns exec "$NS" \
    "$APP" -t "$CTL" upcall/show || true

echo
echo "=================================================="
echo "6. VERIFY UKEY WAS CREATED"
echo "=================================================="

UKEY_BEFORE=$(
    ip netns exec "$NS" \
        "$APP" -t "$CTL" upcall/show 2>/dev/null |
        awk '/keys/ {
            gsub(/[^0-9]/, "", $3)
            total += $3
        }
        END { print total+0 }'
)

echo "UKEY count before deletion: $UKEY_BEFORE"

if [ "$UKEY_BEFORE" -lt 1 ]; then
    echo "FAIL: no UKEY was created"
    echo
    echo "Recent OVS log:"
    tail -50 "$LOG" || true
    exit 1
fi

echo "PASS: UKEY created"

echo
echo "=================================================="
echo "7. DELETE DATAPATH FLOWS ONLY"
echo "=================================================="

ip netns exec "$NS" \
    "$APP" -t "$CTL" dpctl/del-flows

echo "Datapath flows immediately after deletion:"
ip netns exec "$NS" \
    "$APP" -t "$CTL" dpctl/dump-flows || true

echo
echo "UKEYs should still exist:"
ip netns exec "$NS" \
    "$APP" -t "$CTL" upcall/show || true

echo
echo "=================================================="
echo "8. WAIT FOR FOUR MISSED DUMPS"
echo "=================================================="

START_LINE=$(wc -l < "$LOG")

FOUND_4=0

for i in $(seq 1 30); do
    sleep 0.5

    if tail -n +"$((START_LINE + 1))" "$LOG" 2>/dev/null |
        grep -q 'STALE_UKEY_DEBUG.*missed_dumps=4'
    then
        FOUND_4=1
        break
    fi
done

if [ "$FOUND_4" -ne 1 ]; then
    echo "FAIL: did not observe missed_dumps=4"

    echo
    echo "Relevant recent log:"
    tail -100 "$LOG" |
        grep -E \
        'STALE_UKEY_DEBUG|failed to flow_del|revalidator|udpif keys' \
        || true

    exit 1
fi

echo "PASS: missed_dumps=4 observed"

echo
echo "=================================================="
echo "9. VERIFY COMPLETE MISS SEQUENCE"
echo "=================================================="

tail -n +"$((START_LINE + 1))" "$LOG" |
    grep 'STALE_UKEY_DEBUG' |
    tail -20

for n in 1 2 3 4; do
    if tail -n +"$((START_LINE + 1))" "$LOG" |
        grep -q "STALE_UKEY_DEBUG.*missed_dumps=$n"
    then
        echo "PASS: missed_dumps=$n"
    else
        echo "FAIL: missed_dumps=$n not observed"
        exit 1
    fi
done

echo
echo "=================================================="
echo "10. VERIFY DATAPATH DELETE ATTEMPT"
echo "=================================================="

if tail -n +"$((START_LINE + 1))" "$LOG" |
    grep -q 'failed to flow_del (No such file or directory)'
then
    echo "PASS: datapath delete attempted"
else
    echo "FAIL: expected flow_del ENOENT not observed"
    exit 1
fi

echo
echo "=================================================="
echo "11. VERIFY COVERAGE"
echo "=================================================="

COVERAGE=$(
    ip netns exec "$NS" \
        "$APP" -t "$CTL" coverage/show
)

echo "$COVERAGE" |
    grep 'revalidate_missing_dp_flow' || true

if echo "$COVERAGE" |
    grep -q 'revalidate_missing_dp_flow.*total: [1-9]'
then
    echo "PASS: revalidate_missing_dp_flow coverage reached"
else
    echo "FAIL: revalidate_missing_dp_flow coverage not reached"
    exit 1
fi

echo
echo "=================================================="
echo "12. FINAL STATE"
echo "=================================================="

echo "Final datapath flows:"
ip netns exec "$NS" \
    "$APP" -t "$CTL" dpctl/dump-flows || true

echo
echo "Final UKEY state:"
FINAL_UKEY_OUTPUT=$(ip netns exec "$NS" \
    "$APP" -t "$CTL" upcall/show)

echo "$FINAL_UKEY_OUTPUT"

FINAL_UKEY_COUNT=$(echo "$FINAL_UKEY_OUTPUT" | \
    awk '/keys/ {
        gsub(/[^0-9]/, "", $3)
        total += $3
    }
    END { print total+0 }')

echo
echo "Final UKEY count: $FINAL_UKEY_COUNT"

if [ "$FINAL_UKEY_COUNT" -ne 0 ]; then
    echo "FAIL: stale UKEYs remain after cleanup"
    exit 1
fi

echo "PASS: all stale UKEYs were removed"

echo
echo "=================================================="
echo "13. SAVE EVIDENCE"
echo "=================================================="

cp "$LOG" "$EVIDENCE/ovs-vswitchd.log"

ip netns exec "$NS" \
    "$APP" -t "$CTL" upcall/show \
    > "$EVIDENCE/upcall-final.txt"

ip netns exec "$NS" \
    "$APP" -t "$CTL" dpctl/dump-flows \
    > "$EVIDENCE/dp-final.txt" 2>&1 || true

ip netns exec "$NS" \
    "$APP" -t "$CTL" coverage/show \
    > "$EVIDENCE/coverage-final.txt"

tail -n +"$((START_LINE + 1))" "$LOG" |
    grep -E \
    'STALE_UKEY_DEBUG|failed to flow_del' \
    > "$EVIDENCE/stale-ukey-debug.log" || true

echo
echo "Evidence:"
ls -lh "$EVIDENCE"

echo
echo "=================================================="
echo "STALE UKEY REPRODUCTION: PASS"
echo "=================================================="
