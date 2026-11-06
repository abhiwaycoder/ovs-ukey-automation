#!/usr/bin/env bash
# Capture read-only package, service, OVS, and filesystem state on a disposable
# RHEL 8.10 validation VM. This script does not install, remove, or restart OVS.

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

usage() {
    cat <<'USAGE'
Usage:
  sudo OVS_UKEY_DISPOSABLE_TEST_SYSTEM=YES \
    bash scripts/capture_ovs_package_state.sh \
      --label before-upgrade \
      --output-dir /var/tmp/ovs-ukey-lifecycle/before-upgrade

Required:
  --label LABEL         Evidence label (for example before-install or after-upgrade)
  --output-dir DIR      New output directory; existing directories are refused

Safety:
  - Runs only on RHEL 8.10.
  - Requires OVS_UKEY_DISPOSABLE_TEST_SYSTEM=YES.
  - Requires root to collect package, service, and OVS state.
  - Read-only with respect to packages and OVS; writes only to --output-dir.
USAGE
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

LABEL=""
OUT=""

while (($#)); do
    case "$1" in
        --label)
            (($# >= 2)) || die "--label requires a value"
            LABEL=$2
            shift 2
            ;;
        --output-dir)
            (($# >= 2)) || die "--output-dir requires a path"
            OUT=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unknown argument: $1 (use --help)"
            ;;
    esac
done

[[ -n "$LABEL" ]] || die "--label is required"
[[ "$LABEL" =~ ^[A-Za-z0-9._-]+$ ]] || die "Invalid label: $LABEL"
[[ -n "$OUT" ]] || die "--output-dir is required"
[[ "$OUT" = /* ]] || die "--output-dir must be an absolute path"
[[ ! -e "$OUT" ]] || die "Output directory already exists: $OUT"

[[ "$EUID" -eq 0 ]] || die "Run as root (for example, with sudo)"
[[ "${OVS_UKEY_DISPOSABLE_TEST_SYSTEM:-}" == "YES" ]] ||
    die "Set OVS_UKEY_DISPOSABLE_TEST_SYSTEM=YES only on a disposable test VM"

[[ -r /etc/os-release ]] || die "Cannot read /etc/os-release"
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == "rhel" ]] || die "Expected Red Hat Enterprise Linux; found ID=${ID:-unknown}"
[[ "${VERSION_ID:-}" == "8.10" ]] ||
    die "Expected RHEL 8.10; found VERSION_ID=${VERSION_ID:-unknown}"

for command in rpm systemctl sha256sum find sort; do
    command -v "$command" >/dev/null 2>&1 || die "Required command not found: $command"
done

mkdir -p -- "$OUT"
OUT=$(realpath -e -- "$OUT")

capture() {
    local name=$1
    shift
    local rc=0

    {
        printf 'Capture: %s\n' "$name"
        printf 'Label: %s\n' "$LABEL"
        printf 'UTC: %s\n\n' "$(date -u +%FT%TZ)"
        "$@" || rc=$?
        printf '\nCOMMAND_EXIT_CODE=%s\n' "$rc"
    } > "$OUT/$name.txt" 2>&1
}

capture_shell() {
    local name=$1
    local command_text=$2
    capture "$name" bash -c "$command_text"
}

{
    printf 'Label: %s\n' "$LABEL"
    printf 'Captured UTC: %s\n' "$(date -u +%FT%TZ)"
    printf 'Hostname: %s\n' "$(hostname -f 2>/dev/null || hostname)"
    printf 'OS: %s\n' "${PRETTY_NAME:-unknown}"
    printf 'Kernel: %s\n' "$(uname -r)"
    printf 'Kernel architecture: %s\n' "$(uname -m)"
} > "$OUT/metadata.txt"

capture "os-release" cat /etc/os-release
capture "kernel" uname -a
capture "memory" free -h
capture "filesystem" df -hT
capture "installed-ovs-packages" \
    rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' \
    'openvswitch*' 'python3-openvswitch*' 'network-scripts-openvswitch*'
capture "installed-main-package-signature" \
    rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\nSIGPGP=%{SIGPGP:pgpsig}\n' \
    openvswitch2.17
capture "rpm-verify-main-package" rpm -V openvswitch2.17
capture "service-status" \
    systemctl --no-pager --full status openvswitch ovsdb-server ovs-vswitchd
capture "ovs-topology" ovs-vsctl show
capture "ovs-upcall-state" ovs-appctl -t ovs-vswitchd upcall/show
capture "ovs-datapath-flows" ovs-appctl -t ovs-vswitchd dpctl/dump-flows
capture "ovs-coverage" ovs-appctl -t ovs-vswitchd coverage/show

capture_shell "ovs-database-metadata" '
for path in \
  /etc/openvswitch/conf.db \
  /etc/openvswitch/system-id.conf \
  /var/lib/openvswitch
do
  if [[ -e "$path" ]]; then
    stat -c "%F | %U:%G | mode=%a | size=%s | %n" "$path"
  else
    printf "NOT_PRESENT: %s\n" "$path"
  fi
done
'

capture_shell "ovs-binary-checksums" '
for name in ovs-vswitchd ovsdb-server ovs-vsctl ovs-appctl; do
  path=$(command -v "$name" || true)
  if [[ -n "$path" ]]; then
    printf "%s -> %s\n" "$name" "$(readlink -f "$path")"
    sha256sum "$(readlink -f "$path")"
  else
    printf "NOT_FOUND: %s\n" "$name"
  fi
done
'

(
    cd "$OUT"
    find . -maxdepth 1 -type f -name '*.txt' -printf '%f\0' |
        sort -z |
        xargs -0 -r sha256sum
) > "$OUT/SHA256SUMS"

(
    cd "$OUT"
    sha256sum --check SHA256SUMS
)

printf 'Package state captured successfully.\n'
printf 'Label: %s\n' "$LABEL"
printf 'Evidence directory: %s\n' "$OUT"
printf 'Manifest: %s/SHA256SUMS\n' "$OUT"
