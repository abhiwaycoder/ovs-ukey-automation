#!/usr/bin/env bash
# Install the restricted runtime reproduction entry point on a dedicated
# GitHub Actions self-hosted runner. Run from a checked-out repository.

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

usage() {
    cat <<'USAGE'
Usage:
  sudo bash scripts/install_runtime_runner.sh --runner-user gha-runner

Options:
  --runner-user USER   Linux account used by the GitHub Actions runner
  -h, --help           Show this help

The installer:
  - installs the reproduction script under /usr/local/libexec;
  - installs /usr/local/sbin/ovs-ukey-ci as its fixed entry point;
  - creates /etc/ovs-ukey-ci.conf from the example if it is absent; and
  - grants the runner account passwordless sudo for that one command only.

It does not prepare the OVS runtime, compile OVS, or start/restart services.
USAGE
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

RUNNER_USER=""
while (($#)); do
    case "$1" in
        --runner-user)
            (($# >= 2)) || die "--runner-user requires a value"
            RUNNER_USER=$2
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

[[ "$EUID" -eq 0 ]] || die "Run this installer with sudo."
[[ -n "$RUNNER_USER" ]] || die "--runner-user is required"
id "$RUNNER_USER" >/dev/null 2>&1 || die "Runner user does not exist: $RUNNER_USER"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPRO_SCRIPT="$REPO_ROOT/scripts/reproduce_stale_ukey.sh"
WRAPPER_SOURCE="$REPO_ROOT/scripts/ovs-ukey-ci"
CONFIG_SOURCE="$REPO_ROOT/config/ovs-ukey-ci.conf.example"
RUNNER_GROUP="$(id -gn "$RUNNER_USER")"

for file in "$REPRO_SCRIPT" "$WRAPPER_SOURCE" "$CONFIG_SOURCE"; do
    [[ -f "$file" ]] || die "Required repository file is missing: $file"
done

command -v visudo >/dev/null 2>&1 || die "visudo is required to validate the sudoers rule"
command -v install >/dev/null 2>&1 || die "install command is required"

LIBEXEC_DIR="/usr/local/libexec/ovs-ukey-ci"
CONFIG_DEST="/etc/ovs-ukey-ci.conf"
SUDOERS_DEST="/etc/sudoers.d/ovs-ukey-ci-$RUNNER_USER"
EXPECTED_RULE="$RUNNER_USER ALL=(root) NOPASSWD: /usr/local/sbin/ovs-ukey-ci"

install -d -o root -g root -m 0755 "$LIBEXEC_DIR"
install -o root -g root -m 0755 "$REPRO_SCRIPT" "$LIBEXEC_DIR/reproduce_stale_ukey.sh"
install -o root -g root -m 0755 "$WRAPPER_SOURCE" /usr/local/sbin/ovs-ukey-ci

if [[ ! -e "$CONFIG_DEST" ]]; then
    install -o root -g root -m 0600 "$CONFIG_SOURCE" "$CONFIG_DEST"
    sed -i "s/^OVS_UKEY_RUNNER_GROUP=.*/OVS_UKEY_RUNNER_GROUP=\"$RUNNER_GROUP\"/" "$CONFIG_DEST"
else
    [[ -f "$CONFIG_DEST" ]] || die "$CONFIG_DEST exists and is not a regular file"
    [[ "$(stat -c '%u' "$CONFIG_DEST")" == "0" ]] || die "$CONFIG_DEST must be owned by root"
    config_mode="$(stat -c '%a' "$CONFIG_DEST")"
    (( (8#$config_mode & 0022) == 0 )) || die "$CONFIG_DEST must not be group- or world-writable"
fi

if [[ -e "$SUDOERS_DEST" ]]; then
    [[ -f "$SUDOERS_DEST" ]] || die "$SUDOERS_DEST exists and is not a regular file"
    grep -Fxq "$EXPECTED_RULE" "$SUDOERS_DEST" || die "$SUDOERS_DEST exists with a different rule; review it manually"
else
    sudoers_tmp="$(mktemp)"
    trap 'rm -f "$sudoers_tmp"' EXIT
    printf '%s\n' "$EXPECTED_RULE" > "$sudoers_tmp"
    chmod 0440 "$sudoers_tmp"
    visudo -cf "$sudoers_tmp" >/dev/null || die "Generated sudoers rule failed validation"
    install -o root -g root -m 0440 "$sudoers_tmp" "$SUDOERS_DEST"
    rm -f "$sudoers_tmp"
    trap - EXIT
fi

visudo -cf "$SUDOERS_DEST" >/dev/null || die "Installed sudoers file failed validation"

printf 'Runtime runner entry point installed.\n'
printf 'Runner user: %s\n' "$RUNNER_USER"
printf 'Runner primary group: %s\n' "$RUNNER_GROUP"
printf 'Entry point: /usr/local/sbin/ovs-ukey-ci\n'
printf 'Configuration: %s\n' "$CONFIG_DEST"
printf '\nReview and edit the root-owned configuration before running Actions:\n'
printf '  sudoedit %s\n' "$CONFIG_DEST"
printf '\nConfirm that the configured source tree contains the STALE_UKEY_DEBUG-instrumented build.\n'
printf 'The entry point does not build or start OVS; it only runs the isolated reproduction.\n'
