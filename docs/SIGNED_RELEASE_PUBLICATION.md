# Preparing and publishing the signed OVS RPM bundle

This guide packages the signed OVS 2.17.0-106.el8 binaries and their signed local DNF repository into a verifiable download bundle. It can also create a GitHub **draft release** after all local checks pass.

The script does not create signatures and does not need the private signing key. Keep the private key and its GPG home on the protected signing workstation.

## 1. Required files

The signing workstation should contain:

- Signed RPMs under `~/ovs-ukey-signing/signed-release/RPMS/`.
- The single signed source RPM under `~/ovs-ukey-signing/signed-release/SRPMS/`.
- The local binary DNF repository under `~/ovs-ukey-signing/local-repo/`.
- The detached metadata signature at `local-repo/repodata/repomd.xml.asc`.
- The exported public key `keys/RPM-GPG-KEY-OVS-STALE-UKEY` from this repository.

The expected project signing-key fingerprint is:

`7F34141A60E9B91DABF3978DFEC22E62BB0AD5CB`

Verify the fingerprint independently before using the public key. The script rejects a key with any other fingerprint.

## 2. What the script verifies

`scripts/package_signed_ovs_release.sh` performs these checks before creating a bundle:

1. Requires exactly nine binary RPMs in the local repository and one source RPM in the signed-release directory.
2. Verifies the public-key fingerprint against the project fingerprint.
3. Imports only the public key into temporary, isolated RPM and GPG databases.
4. Checks every RPM signature and package digest.
5. Verifies the detached OpenPGP signature on `repodata/repomd.xml`.
6. Checks the local repository `SHA256SUMS` manifest when one is present.
7. Creates a bundle containing the DNF repository, signed source RPM, public key, release information, and a new SHA-256 manifest.
8. Creates a compressed archive and a checksum file beside it.

The temporary verification databases are removed when the script exits. The script does not modify the original signed RPMs or the local repository.

## 3. Prepare a bundle locally

Run this from a clone of the project on the signing workstation:

```bash
bash scripts/package_signed_ovs_release.sh \
  --signed-release-dir "$HOME/ovs-ukey-signing/signed-release" \
  --repo-dir "$HOME/ovs-ukey-signing/local-repo" \
  --public-key "$PWD/keys/RPM-GPG-KEY-OVS-STALE-UKEY" \
  --tag ovs-2.17.0-106.el8-stale-ukey-signed-20261106 \
  --output-dir /var/tmp/ovs-ukey-release
```

Without `--create-draft`, the script only verifies the inputs and creates the local archive. Review its output and verify the resulting archive checksum:

```bash
cd /var/tmp/ovs-ukey-release
sha256sum --check ovs-ukey-signed-el8-repository-ovs-2.17.0-106.el8-stale-ukey-signed-20261106.tar.gz.sha256
```

The archive includes the signed DNF repository at `repo/`, the signed source RPM at `SRPMS/`, the public key at `keys/`, and a `SHA256SUMS` manifest for the bundled contents.

## 4. Create a GitHub draft release

After reviewing the local bundle, authenticate GitHub CLI (`gh`) to the `abhiwaycoder/ovs-ukey-automation` repository.

Run the same command with `--create-draft`:

```bash
bash scripts/package_signed_ovs_release.sh \
  --signed-release-dir "$HOME/ovs-ukey-signing/signed-release" \
  --repo-dir "$HOME/ovs-ukey-signing/local-repo" \
  --public-key "$PWD/keys/RPM-GPG-KEY-OVS-STALE-UKEY" \
  --tag ovs-2.17.0-106.el8-stale-ukey-signed-20261106 \
  --title "OVS 2.17.0-106.el8 signed stale-UKEY packages" \
  --output-dir /var/tmp/ovs-ukey-release \
  --create-draft
```

The script creates a GitHub **draft** release and attaches:

- The signed repository bundle archive.
- The archive's SHA-256 checksum file.
- The public signing key.

Review the release title, notes, tag, bundle, package counts, public key, and checksums in GitHub before publishing the draft. The script refuses to overwrite an existing release/tag.

## 5. Using the downloaded bundle

The release asset is a downloadable snapshot of a DNF repository; it is not itself a hosted DNF `baseurl`.

After downloading and extracting the archive on a disposable RHEL 8.10 test VM:

1. Verify the archive checksum.
2. Verify the public-key fingerprint independently.
3. Verify `SHA256SUMS` inside the extracted bundle.
4. Configure DNF with a local `file://` base URL pointing to the extracted `repo/` directory and with both `gpgcheck=1` and `repo_gpgcheck=1`.
5. Test package discovery, signature verification, installation, upgrade, and rollback in the disposable VM.

To make the repository available as a remote DNF `baseurl`, publish the extracted `repo/` directory through an approved static web server or package-repository hosting service. Do not use a GitHub Release download URL as a DNF repository base URL.

## Safety

- Never copy the private signing key or GPG home into the repository or release bundle.
- Publish only the checked and signed November 3 RPM set, not the earlier November 2 `--nocheck` release assets.
- Verify the exact public-key fingerprint through an independently authenticated channel.
- Test the bundle on disposable RHEL 8.10 systems before broader distribution.
- A GitHub draft release is not public until it is explicitly published in GitHub.
