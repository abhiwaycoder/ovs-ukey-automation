#!/bin/bash
set -euo pipefail

R=/root/ovs-debug-runtime4
NS=ovs-ukey-ns
BR=ukey-br
OVS_VSCTL=/root/ovs-3.5.3/utilities/ovs-vsctl
DB=unix:$R/run/db.sock
APP=/root/ovs-3.5.3/utilities/ovs-appctl
OVS_VSWITCHD=/root/ovs-3.5.3/vswitchd/.libs/lt-ovs-vswitchd

CTL="$R/run/ovs-vswitchd.ctl"
LOG="$R/logs/ovs-vswitchd.log"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
EVIDENCE="/var/lib/ovs-ukey-ci/evidence"

export LD_LIBRARY_PATH="/root/ovs-3.5.3/ovsdb/.libs:/root/ovs-3.5.3/ofproto/.libs:/root/ovs-3.5.3/lib/.libs"

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

VETH1="ukey-veth1"
PEER1="ukey-peer1"
VETH2="ukey-veth2"
PEER2="ukey-peer2"

echo "--- Clean stale test interfaces ---"

# Clean only the bridge and interfaces belonging to the disposable runtime.
"$OVS_VSCTL" --db="$DB" --if-exists del-br "$BR" || true
ip netns exec "$NS" ip link del "$VETH1" 2>/dev/null || true
ip netns exec "$NS" ip link del "$VETH2" 2>/dev/null || true
ip link del "$VETH1" 2>/dev/null || true
ip link del "$VETH2" 2>/dev/null || true
ip link del "$PEER1" 2>/dev/null || true
ip link del "$PEER2" 2>/dev/null || true

echo "--- Create fresh veth pairs in root namespace ---"

# The disposable ovs-vswitchd runs in its own network namespace.
# Create the veth pairs in the root namespace, then move the
# OVS-facing ends into ovs-vswitchd's namespace.

if [ ! -s "$R/run/ovs-vswitchd.pid" ]; then
    echo "ERROR: disposable ovs-vswitchd PID file is missing or empty"
    exit 1
fi

OVS_PID="$(cat "$R/run/ovs-vswitchd.pid")"

if [ -z "$OVS_PID" ] || ! [[ "$OVS_PID" =~ ^[0-9]+$ ]]; then
    echo "ERROR: invalid disposable ovs-vswitchd PID"
    exit 1
fi

if [ ! -r "/proc/$OVS_PID/cmdline" ] ||
   ! tr '\0' ' ' < "/proc/$OVS_PID/cmdline" |
       grep -Fq "$R/run/db.sock"; then
    echo "ERROR: PID file does not identify the runtime4 ovs-vswitchd"
    exit 1
fi

echo "Disposable ovs-vswitchd PID: $OVS_PID"
echo "Disposable ovs-vswitchd netns: $(readlink "/proc/$OVS_PID/ns/net")"

ip link del "$VETH1" 2>/dev/null || true
ip link del "$VETH2" 2>/dev/null || true
ip link del "$PEER1" 2>/dev/null || true
ip link del "$PEER2" 2>/dev/null || true

ip link add "$VETH1" type veth peer name "$PEER1"
ip link add "$VETH2" type veth peer name "$PEER2"

echo "--- Move OVS-facing veth ends into disposable OVS namespace ---"

ip link set "$VETH1" netns "$OVS_PID"
ip link set "$VETH2" netns "$OVS_PID"

echo "--- Bring interfaces up ---"

ip link set "$PEER1" up
ip link set "$PEER2" up

nsenter -t "$OVS_PID" -n ip link set "$VETH1" up
nsenter -t "$OVS_PID" -n ip link set "$VETH2" up

echo "--- Configure deterministic IPv6 link-local addresses ---"

ip -6 addr add fe80::1/64 dev "$PEER1"
ip -6 addr add fe80::2/64 dev "$PEER2"

echo "--- Reset bridge in disposable OVS database only ---"
"$OVS_VSCTL" --db="$DB" --if-exists del-br "$BR"

echo "--- Create disposable OVS bridge ---"

"$OVS_VSCTL" --db="$DB" \
    --may-exist add-br "$BR"

"$OVS_VSCTL" --db="$DB" \
    set bridge "$BR" fail-mode=standalone

echo "--- Attach both veths to disposable OVS bridge ---"

"$OVS_VSCTL" --db="$DB" \
    --may-exist add-port "$BR" "$VETH1"

"$OVS_VSCTL" --db="$DB" \
    --may-exist add-port "$BR" "$VETH2"

echo "Bridge:"
nsenter -t "$OVS_PID" -n ip -br link show "$BR"

echo "Veth1:"
nsenter -t "$OVS_PID" -n ip -br link show "$VETH1"

echo "Peer1:"
ip -br link show "$PEER1"

echo "Veth2:"
nsenter -t "$OVS_PID" -n ip -br link show "$VETH2"

echo "Peer2:"
ip -br link show "$PEER2"


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

echo "--- Peer1 configuration ---"
ip -4 addr show dev "$PEER1"

echo "--- Peer2 configuration ---"
ip -4 addr show dev "$PEER2"

echo "--- IPv6 connectivity test through OVS ---"
ping -6 -I "$PEER1" -c 5 -W 2 fe80::2

sleep 1

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

START_LINE=$(wc -l < "$LOG")

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
echo "Final state recorded; newly created flows/UKEYs are not treated as a failure."

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

# Keep the real datapath dump, even when it is empty.
# Never synthesize evidence that the command did not return.

ip netns exec "$NS" \
    "$APP" -t "$CTL" coverage/show \
    > "$EVIDENCE/coverage-final.txt"

tail -n +"$((START_LINE + 1))" "$LOG" |
    grep -E \
    'STALE_UKEY_DEBUG|failed to flow_del' \
    > "$EVIDENCE/stale-ukey-debug.log" || true

echo
# Evidence is generated by the root-owned reproduction but consumed
# by the unprivileged GitHub Actions runner.
chgrp -R gha-runner "$EVIDENCE"
chmod 0750 "$EVIDENCE"
find "$EVIDENCE" -type f -exec chmod 0640 {} +

echo "Evidence:"
ls -lh "$EVIDENCE"

echo
echo "=================================================="
echo "STALE UKEY REPRODUCTION: PASS"
echo "=================================================="
