#!/usr/bin/env bash
# Build Open vSwitch RPMs from a clean source RPM plus the stale-UKEY patch.
# Run this script inside an EL8-compatible build environment with build
# dependencies already installed. It does not download inputs or install RPMs.

set -Eeuo pipefail
IFS=$'\n\t'

usage() {
    cat <<'USAGE'
Usage:
  bash scripts/build_rpm.sh --srpm FILE --patch FILE --topdir DIR [options]

Required:
  --srpm FILE       Original, unmodified Open vSwitch source RPM
  --patch FILE      Stale-UKEY patch to add as Patch1
  --topdir DIR      New/empty rpmbuild top directory

Options:
  --jobs N          Parallel build jobs (default: 1)
  --dist TAG        Set the RPM dist macro, e.g. el8 (default: environment)
  --with-check      Run the spec %check section (default: --nocheck)
  -h, --help        Show this help

The script refuses a source RPM whose embedded spec already contains Patch1,
to avoid applying the stale-UKEY patch twice. Build outputs, build.log, and
SHA256SUMS are written below --topdir.
USAGE
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

SRPM=""
PATCH_FILE=""
TOPDIR=""
JOBS=1
DIST=""
WITH_CHECK=0

while (($#)); do
    case "$1" in
        --srpm)
            (($# >= 2)) || die "--srpm requires a path"
            SRPM=$2
            shift 2
            ;;
        --patch)
            (($# >= 2)) || die "--patch requires a path"
            PATCH_FILE=$2
            shift 2
            ;;
        --topdir)
            (($# >= 2)) || die "--topdir requires a path"
            TOPDIR=$2
            shift 2
            ;;
        --jobs)
            (($# >= 2)) || die "--jobs requires a number"
            JOBS=$2
            shift 2
            ;;
        --dist)
            (($# >= 2)) || die "--dist requires a tag"
            DIST=$2
            shift 2
            ;;
        --with-check)
            WITH_CHECK=1
            shift
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

[[ -n "$SRPM" ]] || die "--srpm is required"
[[ -n "$PATCH_FILE" ]] || die "--patch is required"
[[ -n "$TOPDIR" ]] || die "--topdir is required"
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || die "--jobs must be a positive integer"
[[ -z "$DIST" || "$DIST" =~ ^[A-Za-z0-9_]+$ ]] || die "--dist must contain only letters, digits, and underscores"

for command in rpm rpmbuild rpm2cpio cpio sha256sum find sort xargs realpath mktemp; do
    command -v "$command" >/dev/null 2>&1 || die "Required command not found: $command"
done

SRPM=$(realpath -e -- "$SRPM") || die "Cannot resolve source RPM path"
PATCH_FILE=$(realpath -e -- "$PATCH_FILE") || die "Cannot resolve patch path"
[[ -f "$SRPM" ]] || die "Source RPM is not a regular file: $SRPM"
[[ -f "$PATCH_FILE" ]] || die "Patch is not a regular file: $PATCH_FILE"

TOPDIR=$(realpath -m -- "$TOPDIR")
[[ "$TOPDIR" = /* ]] || die "--topdir must resolve to an absolute path"
[[ "$TOPDIR" != *" "* ]] || die "--topdir must not contain spaces"

if [[ -e "$TOPDIR" ]]; then
    [[ -d "$TOPDIR" ]] || die "--topdir exists and is not a directory"
    [[ -z "$(find "$TOPDIR" -mindepth 1 -maxdepth 1 -print -quit)" ]] ||
        die "--topdir must be empty; refusing to overwrite existing build data"
fi

mkdir -p "$TOPDIR"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ovs-rpm-build.XXXXXX")
cleanup() {
    local status=$?
    if ((status != 0)); then
        printf 'Build failed (exit %s). Inspect %s/build.log if it exists.\n' \
            "$status" "$TOPDIR" >&2
    fi
    rm -rf -- "$WORK"
    return "$status"
}
trap cleanup EXIT

EXTRACT="$WORK/srpm"
mkdir -p "$EXTRACT"

printf '%s\n' "========== Source RPM metadata =========="
rpm -qp --qf 'Name: %{NAME}\nVersion: %{VERSION}\nRelease: %{RELEASE}\nArchitecture: %{ARCH}\n' "$SRPM"

printf '%s\n' "========== Extract source RPM =========="
rpm2cpio "$SRPM" | (cd "$EXTRACT" && cpio -idm --quiet)

mapfile -t SPEC_FILES < <(find "$EXTRACT" -maxdepth 1 -type f -name '*.spec' -print)
(("${#SPEC_FILES[@]}" == 1)) ||
    die "Expected exactly one spec file in the source RPM; found ${#SPEC_FILES[@]}"

ORIGINAL_SPEC="${SPEC_FILES[0]}"
SPEC_NAME=$(basename "$ORIGINAL_SPEC")
SPEC_PATH="$TOPDIR/SPECS/$SPEC_NAME"
PATCH_NAME="openvswitch-2.17.0-stale-ukey.patch"

# Guard against using an SRPM that already includes the stale-UKEY patch.
if grep -Eq '^Patch1:' "$ORIGINAL_SPEC" ||
   grep -Fq "$PATCH_NAME" "$ORIGINAL_SPEC"; then
    die "The source RPM spec already references Patch1 or $PATCH_NAME; use the clean original SRPM"
fi

PATCH_COUNT=$(grep -Ec '^Patch:[[:space:]]*openvswitch-' "$ORIGINAL_SPEC" || true)
PREP_COUNT=$(grep -Fc '%patch -p1' "$ORIGINAL_SPEC" || true)
[[ "$PATCH_COUNT" -eq 1 ]] ||
    die "Expected one unnumbered vendor Patch: entry; found $PATCH_COUNT"
[[ "$PREP_COUNT" -eq 1 ]] ||
    die "Expected one '%patch -p1' invocation; found $PREP_COUNT"

cp -a "$EXTRACT/." "$TOPDIR/SOURCES/"
cp "$PATCH_FILE" "$TOPDIR/SOURCES/$PATCH_NAME"
cp "$ORIGINAL_SPEC" "$SPEC_PATH"

# Preserve patch order: apply the vendor patch first, then the stale-UKEY fix.
sed -i '/^Patch:[[:space:]]*openvswitch-/a Patch1: openvswitch-2.17.0-stale-ukey.patch' "$SPEC_PATH"
sed -i '/^%patch -p1$/a %patch1 -p1' "$SPEC_PATH"

grep -Fqx 'Patch1: openvswitch-2.17.0-stale-ukey.patch' "$SPEC_PATH" ||
    die "Patch1 was not inserted into the spec"
grep -Fqx '%patch1 -p1' "$SPEC_PATH" ||
    die "%patch1 invocation was not inserted into %prep"

printf '%s\n' "========== Patch input =========="
sha256sum "$PATCH_FILE" "$TOPDIR/SOURCES/$PATCH_NAME"
printf '%s\n' "========== Effective spec patch entries =========="
grep -nE '^(Patch[0-9]*:|%patch)' "$SPEC_PATH"

BUILD_ARGS=(
    --define "_topdir $TOPDIR"
    --define "_smp_mflags -j$JOBS"
)
if [[ -n "$DIST" ]]; then
    BUILD_ARGS+=(--define "dist .$DIST")
fi
if ((WITH_CHECK == 0)); then
    BUILD_ARGS+=(--nocheck)
    printf '%s\n' "NOTE: RPM %check is skipped (default). Use --with-check to enable it."
else
    printf '%s\n' "NOTE: RPM %check is enabled."
fi

printf '%s\n' "========== Build RPMs =========="
rpmbuild "${BUILD_ARGS[@]}" -ba "$SPEC_PATH" 2>&1 | tee "$TOPDIR/build.log"

mapfile -d '' RPM_FILES < <(
    find "$TOPDIR/RPMS" "$TOPDIR/SRPMS" -type f -name '*.rpm' -print0 | sort -z
)
(("${#RPM_FILES[@]}" > 0)) || die "rpmbuild completed but produced no RPM files"

printf '%s\n' "========== Verify RPM digests =========="
for rpm_file in "${RPM_FILES[@]}"; do
    rpm -K "$rpm_file"
done

(
    cd "$TOPDIR"
    find RPMS SRPMS -type f -name '*.rpm' -print0 |
        sort -z |
        xargs -0 -r sha256sum
) > "$TOPDIR/SHA256SUMS"

printf '%s\n' "========== Generated package NEVRAs =========="
for rpm_file in "${RPM_FILES[@]}"; do
    rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' "$rpm_file"
done

printf '%s\n' "========== SHA256SUMS =========="
cat "$TOPDIR/SHA256SUMS"

printf 'RPM build completed successfully. Artifacts: %s\n' "$TOPDIR"
