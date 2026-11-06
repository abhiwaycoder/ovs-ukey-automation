# Native RHEL 8.10 package lifecycle validation

This runbook describes how to validate the signed OVS stale-UKEY RPM package on a disposable RHEL 8.10 VM. It covers first installation, a version-to-version upgrade, rollback, service checks, and evidence collection.

The package-state capture helper is read-only. It records package versions, package signature metadata, RPM verification output, OVS services, bridge topology, datapath/upcall state, database file ownership, binary checksums, and a SHA-256 manifest.

## 1. Test environment

Use a disposable RHEL 8.10 VM with a recoverable snapshot. Do not use a production OVS host or a node carrying production OpenStack workloads.

The test VM needs:

- RHEL 8.10 and root/sudo access.
- The signed OVS binary RPM repository created during the local signing validation.
- The project public key, with fingerprint independently confirmed as `7F34141A60E9B91DABF3978DFEC22E62BB0AD5CB`.
- The approved baseline OVS package version for upgrade and rollback testing.
- Enough disk space to retain the RPMs, logs, and evidence snapshots.

The signing workstation contains the manually signed package set under `~/ovs-ukey-signing/signed-release/` and the local binary repository under `~/ovs-ukey-signing/local-repo/`. Copy the signed binary repository and public key to the disposable VM using the approved secure file-transfer method. Keep the signed source RPM separately for package provenance.

## 2. Prepare the signed local repository

On the RHEL 8.10 VM, place the copied repository at `/opt/ovs-ukey-signed-repo`. Place the exported public key at `/opt/ovs-ukey-signed-repo/RPM-GPG-KEY-OVS-STALE-UKEY`.

Verify the public-key fingerprint before importing it:

```bash
gpg --show-keys --with-fingerprint \
  /opt/ovs-ukey-signed-repo/RPM-GPG-KEY-OVS-STALE-UKEY
```

Confirm that the full fingerprint is exactly:

`7F34141A60E9B91DABF3978DFEC22E62BB0AD5CB`

Configure DNF to verify both package signatures and signed repository metadata:

```bash
sudo tee /etc/yum.repos.d/ovs-ukey-local.repo >/dev/null <<'EOF'
[ovs-ukey-local]
name=OVS stale UKEY signed test repository
baseurl=file:///opt/ovs-ukey-signed-repo
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=file:///opt/ovs-ukey-signed-repo/RPM-GPG-KEY-OVS-STALE-UKEY
metadata_expire=0
EOF
```

Refresh the repository metadata and inspect the available OVS package:

```bash
sudo dnf clean metadata
sudo dnf --disablerepo='*' --enablerepo=ovs-ukey-local makecache
sudo dnf --disablerepo='*' --enablerepo=ovs-ukey-local list --available 'openvswitch2.17*'
```

Before proceeding, verify that the signed repository contains the expected nine binary packages and that the detached `repomd.xml` signature is present. Do not disable `gpgcheck` or `repo_gpgcheck` to work around a signature or metadata error.

## 3. Capture the system state

Copy the helper from the project repository to the test VM, or run it from a cloned copy of this repository.

The helper refuses to run unless the operating system is RHEL 8.10, the caller is root, the explicit disposable-host acknowledgement is set, and the output directory does not already exist.

Example before a package transaction:

```bash
sudo OVS_UKEY_DISPOSABLE_TEST_SYSTEM=YES \
  bash scripts/capture_ovs_package_state.sh \
    --label before-install \
    --output-dir /var/tmp/ovs-ukey-lifecycle/before-install
```

For later stages, use a new label and a new output directory, for example:

- `before-upgrade`
- `after-upgrade`
- `after-rollback`

The script does not install packages, remove packages, or restart services. It writes diagnostic files and `SHA256SUMS` only under the requested output directory.

## 4. First-install validation

Use a fresh disposable VM or a clean VM snapshot that does not already contain the target OVS package.

1. Capture the pre-install state.
2. Review the DNF transaction before accepting it:

```bash
sudo dnf --enablerepo=ovs-ukey-local --assumeno install openvswitch2.17
```

3. Confirm that the selected package comes from `ovs-ukey-local` and that dependency resolution is expected for this RHEL 8.10 image.
4. Run the reviewed installation transaction:

```bash
sudo dnf --enablerepo=ovs-ukey-local install openvswitch2.17
```

5. Start and enable the OVS services according to the test image's service configuration. Do not apply this step to a host carrying production networking.
6. Capture the post-install state:

```bash
sudo OVS_UKEY_DISPOSABLE_TEST_SYSTEM=YES \
  bash scripts/capture_ovs_package_state.sh \
    --label after-install \
    --output-dir /var/tmp/ovs-ukey-lifecycle/after-install
```

Review the installed package list, package signature metadata, `rpm -V` output, service state, `ovs-vsctl show`, database ownership and mode, and binary checksums.

## 5. Different-NEVRA upgrade validation

A same-NEVRA replacement is not an upgrade test. Use a separate disposable VM or restore the approved baseline snapshot with the known-good older OVS package version installed.

Before upgrading:

1. Record the exact installed package NEVRAs using `rpm -qa`.
2. Confirm that the baseline package set and the candidate signed package set are both available.
3. Capture a `before-upgrade` state.
4. Review the transaction without applying it:

```bash
sudo dnf --enablerepo=ovs-ukey-local --assumeno upgrade openvswitch2.17
```

Verify that DNF plans to upgrade the expected OVS package to `2.17.0-106.el8` and that it does not remove unrelated packages or alter unrelated repositories. If the transaction is unexpected, stop and investigate it.

Apply the reviewed transaction:

```bash
sudo dnf --enablerepo=ovs-ukey-local upgrade openvswitch2.17
```

Check service state, OVS bridge configuration, database ownership and permissions, package verification, and test traffic. Capture `after-upgrade` state in a new directory.

## 6. Rollback validation

Rollback must use a known-good, previously approved OVS package version. Record its exact NEVRA and keep the complete matching RPM set or a trusted repository available before starting the upgrade test.

Review the downgrade transaction first:

```bash
sudo dnf --assumeno downgrade openvswitch2.17-<KNOWN_GOOD_VERSION>-<KNOWN_GOOD_RELEASE>.el8
```

Replace the placeholder with the exact package version available in the approved baseline repository. Do not guess the EVR or use an arbitrary RPM from another build.

After confirming the transaction, apply the downgrade:

```bash
sudo dnf downgrade openvswitch2.17-<KNOWN_GOOD_VERSION>-<KNOWN_GOOD_RELEASE>.el8
```

If DNF cannot find the approved older version, restore the disposable VM snapshot or configure the trusted baseline repository. Do not use `rpm --nodeps`, force an incomplete package downgrade, or remove OVS packages manually to work around dependency resolution.

After rollback, verify that the expected older NEVRA is installed, services are healthy, OVS database ownership and bridge configuration remain valid, and traffic works. Capture `after-rollback` state.

## 7. Compare and verify evidence

Every snapshot contains individual diagnostic files and a checksum manifest. Verify each manifest:

```bash
for dir in \
  /var/tmp/ovs-ukey-lifecycle/before-install \
  /var/tmp/ovs-ukey-lifecycle/after-install \
  /var/tmp/ovs-ukey-lifecycle/before-upgrade \
  /var/tmp/ovs-ukey-lifecycle/after-upgrade \
  /var/tmp/ovs-ukey-lifecycle/after-rollback
do
  [[ -d "$dir" ]] || continue
  (cd "$dir" && sha256sum --check SHA256SUMS)
done
```

Compare the relevant snapshots, for example:

```bash
diff -u \
  /var/tmp/ovs-ukey-lifecycle/before-upgrade/installed-ovs-packages.txt \
  /var/tmp/ovs-ukey-lifecycle/after-upgrade/installed-ovs-packages.txt

diff -u \
  /var/tmp/ovs-ukey-lifecycle/before-upgrade/ovs-database-metadata.txt \
  /var/tmp/ovs-ukey-lifecycle/after-upgrade/ovs-database-metadata.txt
```

Check these outcomes for every stage:

- Expected OVS package NEVRA and signature are installed.
- `rpm -V openvswitch2.17` has no unexplained differences.
- OVS services are active after the service-start stage.
- Existing OVS database ownership and permissions are preserved.
- Expected bridges and ports are present.
- Test traffic works.
- Runtime UKEY cleanup behaves as expected.
- The evidence manifests pass checksum verification.

A non-zero command exit code is recorded in its evidence file. Review those exit codes rather than treating the existence of a snapshot as proof that every check passed.

## 8. Runtime stale-UKEY validation

Package lifecycle testing and stale-UKEY runtime reproduction are separate checks.

After package installation or upgrade, run the dedicated isolated runtime validation procedure on a disposable environment. For the instrumented reproduction, the expected evidence includes:

- The same UKEY progressing through `missed_dumps=1`, `2`, `3`, and `4` in order.
- The datapath deletion attempt.
- A positive `revalidate_missing_dp_flow` coverage counter.
- Final OVS runtime snapshots.

The GitHub Actions workflow `.github/workflows/runtime-reproduction.yml` runs this reproduction on a dedicated self-hosted runner labelled `self-hosted` and `ovs-ukey`. It requires explicit confirmation that the runner is a disposable test environment and uploads the runtime evidence artifact after the run.

## 9. Report template

Record the outcome for each VM/snapshot in the test report:

| Scenario | Baseline NEVRA | Candidate NEVRA | Package result | Service result | Database/config result | Traffic result | Evidence directory |
|---|---|---|---|---|---|---|---|
| First install | Not installed | 2.17.0-106.el8 | | | | | |
| Upgrade | Record exact baseline | 2.17.0-106.el8 | | | | | |
| Rollback | 2.17.0-106.el8 | Record exact baseline | | | | | |

Keep the VM identifier, RHEL minor version, kernel version, transaction output, timestamps, and SHA-256 manifests with the final report.

## Safety

- Use only disposable RHEL 8.10 VMs and isolated test networking.
- Take a VM snapshot before each lifecycle scenario.
- Review every DNF transaction before accepting it.
- Keep the baseline RPM set available before starting an upgrade.
- Do not disable RPM or repository signature verification.
- Do not run package installation, rollback, OVS restart, or bridge changes on production systems.
- Do not place GitHub tokens, private signing keys, or GPG home directories in the evidence directory.
