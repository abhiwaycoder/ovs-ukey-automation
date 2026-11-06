#!/usr/bin/env bash
# Verify signed OVS RPMs and a signed local DNF repository, then bundle them.
# Optional GitHub publication creates a DRAFT release; it never publishes live.

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

EXPECTED_FINGERPRINT="7F34141A60E9B91DABF3978DFEC22E62BB0AD5CB"

usage() {
    cat <<'USAGE'
Usage:
  bash scripts/package_signed_ovs_release.sh \
    --signed-release-dir ~/ovs-ukey-signing/signed-release \
    --repo-dir ~/ovs-ukey-signing/local-repo \
    --public-key keys/RPM-GPG-KEY-OVS-STALE-UKEY \
    --tag ovs-2.17.0-106.el8-stale-ukey-signed-20261106 \
    --output-dir /var/tmp/ovs-ukey-release

Options:
  --title TITLE       Draft release title
  --notes-file FILE   Release notes Markdown file
  --create-draft      Create a GitHub DRAFT release after all local checks pass
  -h, --help          Show this help

Without --create-draft, the script only verifies and creates the release bundle.
It never imports or accesses a private signing key.
USAGE
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

SIGNED_DIR=""
REPO_DIR=""
PUBLIC_KEY=""
TAG=""
TITLE=""
NOTES_FILE=""
OUTPUT_DIR=""
CREATE_DRAFT=0

while (($#)); do
    case "$1" in
        --signed-release-dir) (($# >= 2)) || die "$1 requires a path"; SIGNED_DIR=$2; shift 2 ;;
        --repo-dir)           (($# >= 2)) || die "$1 requires a path"; REPO_DIR=$2; shift 2 ;;
        --public-key)         (($# >= 2)) || die "$1 requires a path"; PUBLIC_KEY=$2; shift 2 ;;
        --tag)                (($# >= 2)) || die "$1 requires a value"; TAG=$2; shift 2 ;;
        --title)              (($# >= 2)) || die "$1 requires a value"; TITLE=$2; shift 2 ;;
        --notes-file)         (($# >= 2)) || die "$1 requires a path"; NOTES_FILE=$2; shift 2 ;;
        --output-dir)         (($# >= 2)) || die "$1 requires a path"; OUTPUT_DIR=$2; shift 2 ;;
        --create-draft)       CREATE_DRAFT=1; shift ;;
        -h|--help)            usage; exit 0 ;;
        *)                    die "Unknown argument: $1 (use --help)" ;;
    esac
done

[[ -n "$SIGNED_DIR" ]] || die "--signed-release-dir is required"
[[ -n "$REPO_DIR" ]] || die "--repo-dir is required"
[[ -n "$PUBLIC_KEY" ]] || die "--public-key is required"
[[ -n "$TAG" ]] || die "--tag is required"
[[ -n "$OUTPUT_DIR" ]] || die "--output-dir is required"
[[ "$TAG" =~ ^[A-Za-z0-9._-]+$ ]] || die "Invalid release tag"

SIGNED_DIR=$(realpath -e -- "$SIGNED_DIR") || die "Cannot resolve signed-release directory"
REPO_DIR=$(realpath -e -- "$REPO_DIR") || die "Cannot resolve local repository directory"
PUBLIC_KEY=$(realpath -e -- "$PUBLIC_KEY") || die "Cannot resolve public key"
OUTPUT_DIR=$(realpath -m -- "$OUTPUT_DIR")

[[ -d "$SIGNED_DIR/SRPMS" ]] || die "Missing SRPMS directory under $SIGNED_DIR"
[[ -d "$REPO_DIR/repodata" ]] || die "Missing repodata directory under $REPO_DIR"
[[ -s "$REPO_DIR/repodata/repomd.xml" ]] || die "Missing repodata/repomd.xml"
[[ -s "$REPO_DIR/repodata/repomd.xml.asc" ]] || die "Missing detached repomd.xml signature"
[[ ! -e "$OUTPUT_DIR" ]] || die "Output directory already exists: $OUTPUT_DIR"

for command in rpm rpmkeys gpg sha256sum find sort xargs tar realpath mktemp awk; do
    command -v "$command" >/dev/null 2>&1 || die "Required command not found: $command"
done

FINGERPRINT=$(gpg --show-keys --with-colons --fingerprint "$PUBLIC_KEY" |
    awk -F: '$1 == "fpr" { print toupper($10); exit }')
[[ "$FINGERPRINT" == "$EXPECTED_FINGERPRINT" ]] ||
    die "Public-key fingerprint mismatch: ${FINGERPRINT:-not found}"

mapfile -d '' BINARY_RPMS < <(
    find "$REPO_DIR" -type f -name '*.rpm' ! -name '*.src.rpm' -print0 | sort -z
)
mapfile -d '' SOURCE_RPMS < <(
    find "$SIGNED_DIR/SRPMS" -maxdepth 1 -type f -name '*.src.rpm' -print0 | sort -z
)

[[ "${#BINARY_RPMS[@]}" -eq 9 ]] ||
    die "Expected exactly 9 signed binary RPMs in local repository; found ${#BINARY_RPMS[@]}"
[[ "${#SOURCE_RPMS[@]}" -eq 1 ]] ||
    die "Expected exactly 1 signed source RPM; found ${#SOURCE_RPMS[@]}"

if [[ -s "$REPO_DIR/SHA256SUMS" ]]; then
    (
        cd "$REPO_DIR"
        sha256sum --check SHA256SUMS
    ) || die "Local repository SHA256SUMS verification failed"
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/ovs-signed-release.XXXXXX")
cleanup() {
    local rc=$?
    rm -rf -- "$TMP"
    return "$rc"
}
trap cleanup EXIT

RPMDB="$TMP/rpmdb"
GPGHOME="$TMP/gnupg"
mkdir -p "$RPMDB" "$GPGHOME"
chmod 0700 "$GPGHOME"

rpm --dbpath "$RPMDB" --initdb
rpmkeys --dbpath "$RPMDB" --import "$PUBLIC_KEY"

for rpm_file in "${BINARY_RPMS[@]}" "${SOURCE_RPMS[@]}"; do
    echo "Verifying signed package: $rpm_file"
    signature=$(rpm -qp --qf '%{SIGPGP:pgpsig}\n' "$rpm_file") || die "Cannot read RPM signature: $rpm_file"
    [[ -n "$signature" && "$signature" != "(none)" ]] || die "RPM has no OpenPGP signature: $rpm_file"
    rpmkeys --dbpath "$RPMDB" --checksig --verbose "$rpm_file"
done

gpg --homedir "$GPGHOME" --batch --import "$PUBLIC_KEY" >/dev/null
gpg --homedir "$GPGHOME" --batch --verify \
    "$REPO_DIR/repodata/repomd.xml.asc" \
    "$REPO_DIR/repodata/repomd.xml"

mkdir -p "$OUTPUT_DIR"
BUNDLE="$TMP/ovs-ukey-signed-release"
mkdir -p "$BUNDLE/repo" "$BUNDLE/SRPMS" "$BUNDLE/keys"
cp -a "$REPO_DIR/." "$BUNDLE/repo/"
cp "${SOURCE_RPMS[0]}" "$BUNDLE/SRPMS/"
cp "$PUBLIC_KEY" "$BUNDLE/keys/RPM-GPG-KEY-OVS-STALE-UKEY"

cat > "$BUNDLE/RELEASE-INFO.txt" <<INFO
Open vSwitch stale-UKEY signed package bundle
Package release: 2.17.0-106.el8
Build environment: Rocky Linux 8.10
Runtime target: RHEL 8.10
Binary RPM count: 9
Source RPM count: 1
RPM signing key fingerprint: $FINGERPRINT
Repository metadata: repomd.xml with detached OpenPGP signature
INFO

(
    cd "$BUNDLE"
    find repo SRPMS keys -type f -print0 |
        sort -z |
        xargs -0 -r sha256sum > SHA256SUMS
    sha256sum --check SHA256SUMS
)

ARCHIVE="$OUTPUT_DIR/ovs-ukey-signed-el8-repository-${TAG}.tar.gz"
tar -C "$TMP" -czf "$ARCHIVE" "$(basename "$BUNDLE")"
(cd "$OUTPUT_DIR" && sha256sum "$(basename "$ARCHIVE")" > "$(basename "$ARCHIVE").sha256")

printf '\nLocal verification and bundle creation: PASS\n'
printf 'Binary RPMs verified: %s\n' "${#BINARY_RPMS[@]}"
printf 'Source RPMs verified: %s\n' "${#SOURCE_RPMS[@]}"
printf 'Public-key fingerprint: %s\n' "$FINGERPRINT"
printf 'Bundle: %s\n' "$ARCHIVE"
printf 'Bundle checksum: %s\n' "$ARCHIVE.sha256"

if ((CREATE_DRAFT == 1)); then
    command -v gh >/dev/null 2>&1 || die "GitHub CLI (gh) is required for --create-draft"
    gh auth status >/dev/null 2>&1 || die "Authenticate gh before creating a draft release"

    if gh release view "$TAG" >/dev/null 2>&1; then
        die "A GitHub release/tag named $TAG already exists; refusing to overwrite it"
    fi

    if [[ -n "$NOTES_FILE" ]]; then
        NOTES_FILE=$(realpath -e -- "$NOTES_FILE") || die "Cannot resolve notes file"
        [[ -f "$NOTES_FILE" ]] || die "Release notes file does not exist"
    else
        NOTES_FILE="$OUTPUT_DIR/release-notes-${TAG}.md"
        cat > "$NOTES_FILE" <<NOTES
# Open vSwitch stale-UKEY signed EL8 package bundle

This draft release contains the locally verified signed Open vSwitch 2.17.0-106.el8 package set and signed DNF repository.

- 9 signed binary RPMs and 1 signed source RPM.
- RPM signatures and header/payload digests verified using the project public key.
- DNF repository metadata signature verified.
- SHA-256 manifest included in the bundle.
- Signing-key fingerprint: \`$FINGERPRINT\`.

The bundle is a downloadable repository snapshot. Extract it on a test system and configure DNF with a local \`file://\` base URL, or publish the extracted repository directory through an approved static web server.

Use only after independently confirming the public-key fingerprint. Test on disposable RHEL 8.10 systems.
NOTES
    fi

    gh release create "$TAG" \
        "$ARCHIVE" \
        "$ARCHIVE.sha256" \
        "$PUBLIC_KEY" \
        --title "${TITLE:-OVS 2.17.0-106.el8 signed stale-UKEY packages}" \
        --notes-file "$NOTES_FILE" \
        --target main \
        --draft

    printf '\nGitHub draft release created. Review its assets and notes before publishing it.\n'
else
    printf '\nNo GitHub release was created. Add --create-draft to upload a draft after review.\n'
fi
