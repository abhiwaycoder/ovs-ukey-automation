# RPM signing and local repository validation — November 3, 2026

**Result: PASS for local signing, package-signature verification, and DNF repository download validation.**

This report records a separate manual signing operation performed on November 3, 2026, using the checked RPM build artifact from GitHub Actions. It does not change the provenance of earlier unsigned release assets and does not mean that the signed packages have been published.

## Source artifact and build provenance

- Workflow: [OVS RPM Build with Tests](https://github.com/abhiwaycoder/ovs-ukey-automation/actions/runs/41572770829)
- Run ID: `41572770829` (run number 7)
- Build commit: `83a4095f614adac7d9eaa1ff847151695515bfa2`
- Workflow artifact: `ovs-rpm-check-validation-41572770829`
- Artifact ID: `13204797978`
- Artifact size: 763,468,404 bytes
- Artifact archive digest reported by GitHub: `sha256:c2d50eca085363376cf94ced4f10ec625c057b194959511223ddc0eae6cc074a`
- Build environment: Rocky Linux 8.10 container on GitHub-hosted infrastructure
- Build mode: `--with-check`
- Full userspace test suite: 2,436 passed, 1 skipped
- Targeted test: 1305, `Cleanup missing datapath flows`, PASS
- Outputs: 9 binary RPMs and 1 source RPM

The artifact was downloaded and its original `SHA256SUMS` manifest was checked successfully for all ten RPMs before signing.

## Signing key

A project-specific OpenPGP signing key was created for this manual signing operation.

| Property | Value |
|---|---|
| User ID | `OVS Stale UKEY RPM Signing` |
| Algorithm | RSA 4096 |
| Created | November 3, 2026 |
| Expiry | November 2, 2028 |
| Fingerprint | `7F34141A60E9B91DABF3978DFEC22E62BB0AD5CB` |
| RPM signature | OpenPGP V4 RSA/SHA512 |

The private key was kept in a separate GPG home on the signing workstation and was not placed in the repository, GitHub Actions, or the RPM artifacts. Only the exported public key was used for verification. The public key file was named `RPM-GPG-KEY-OVS-STALE-UKEY`.

**Publication boundary:** the exported public key is included at [`keys/RPM-GPG-KEY-OVS-STALE-UKEY`](../keys/RPM-GPG-KEY-OVS-STALE-UKEY). Its full fingerprint is `7F34141A60E9B91DABF3978DFEC22E62BB0AD5CB`. The signed RPMs and local repository have not yet been published as release assets or hosted repository content. Consumers should independently verify the full fingerprint through an authenticated channel before trusting packages. Do not treat the fingerprint alone as a substitute for the public key.

## RPM signing and verification

RPM 6 signing was configured to use GnuPG and the full key fingerprint. The signed copies were written to a separate directory; the downloaded original RPMs were preserved.

All ten signed packages passed independent verification against a separate RPM database containing the project public key:

- Header OpenPGP signature: `OK` for all ten RPMs.
- Header SHA-256 digest: `OK` for all ten RPMs.
- Payload SHA-256 digest: `OK` for all ten RPMs.
- Original unsigned/downloaded package manifest: all ten entries remained `OK`.

The signed package checksums are recorded below. They are different from the checksums of the original unsigned RPMs because the RPM signatures were added to the package headers.

### Signed RPM SHA-256 checksums

```text
6037172dd6f6ada574e1732aa8d2e5c500dcb04c12c74bad11aa21df61ad5763  RPMS/noarch/openvswitch2.17-test-2.17.0-106.el8.noarch.rpm
83ac110d4dcdd1281c68e829f7fd4496f5508b10b0e52ee460ccd103b83787e0  RPMS/x86_64/network-scripts-openvswitch2.17-2.17.0-106.el8.x86_64.rpm
2d3b35a6ff9450b2f689c861ae254fa3c138d5c5e4e03de9a67a7f42d70cd3c2  RPMS/x86_64/openvswitch2.17-2.17.0-106.el8.x86_64.rpm
87f0f6056090dba2da27fdfcf3bddad0c98454a2a8001e63116bc4e593f6140a  RPMS/x86_64/openvswitch2.17-debuginfo-2.17.0-106.el8.x86_64.rpm
cd3139328b239d6556abecee2b03615d9df668278de367143002de37be1280fa  RPMS/x86_64/openvswitch2.17-debugsource-2.17.0-106.el8.x86_64.rpm
409cab4ebae42ccee66c1b7018f74937febf6d4c25acb0e3698c73ee16bf7551  RPMS/x86_64/openvswitch2.17-devel-2.17.0-106.el8.x86_64.rpm
2e8d12eaa25ac934e66b6f793b2094e665472f9fb3c5ac377f1809ba4bc442eb  RPMS/x86_64/openvswitch2.17-ipsec-2.17.0-106.el8.x86_64.rpm
a4fbddf03c8faf225f597e067e531972b34fe5bf1f690b653569cc7502c6d65e  RPMS/x86_64/python3-openvswitch2.17-2.17.0-106.el8.x86_64.rpm
c39eeb133999203573422ed86c6585cb3b6e28e188fdc0b11ebef57a0f6290f3  RPMS/x86_64/python3-openvswitch2.17-debuginfo-2.17.0-106.el8.x86_64.rpm
a51916ab550fd13cab05dbe444fae6ec2d513f8362d88d4bbc08f6c9ca5c2682  SRPMS/openvswitch2.17-2.17.0-106.el8.src.rpm
```

## Local repository and DNF validation

A local binary repository was created from the nine signed binary RPMs. The signed source RPM was retained separately.

- Repository metadata generated with `createrepo_c --checksum sha256`.
- `repodata/repomd.xml` signed with a detached ASCII-armored OpenPGP signature.
- The detached metadata signature verified as a good signature from the project key.
- A repository SHA-256 manifest covering the package files, metadata, detached signature, and public key was checked successfully (15 entries).
- DNF5 `makecache --refresh` succeeded with `gpgcheck=1`, `pkg_gpgcheck=1`, and `repo_gpgcheck=1`.
- DNF listed all nine binary packages from the local repository.
- DNF5 `reposync --gpgcheck` downloaded all nine packages.
- All nine downloaded RPMs independently passed `rpmkeys --checksig --verbose` against the isolated RPM database.

This validates local repository metadata authentication, package download, and RPM signature verification. No package installation transaction was run in this phase.

## Scope and limitations

- The signed RPMs and local repository were created on the signing workstation under `~/ovs-ukey-signing/`.
- The signed RPMs have not yet been uploaded as GitHub Release assets or published through a hosted package repository.
- The public key is included at [`keys/RPM-GPG-KEY-OVS-STALE-UKEY`](../keys/RPM-GPG-KEY-OVS-STALE-UKEY); its full fingerprint is recorded above.
- The older November 2 release assets created with `--nocheck` remain separate unsigned artifacts. The November 3 checked build and the signed local copies do not retroactively change those files.
- No OVS package installation, upgrade, rollback, service restart, or OpenStack end-to-end test was performed as part of this signing validation.
- Native EL8 installation/upgrade/rollback testing remains pending in a disposable RHEL 8.10 environment.

The local signed release directory was `signed-release/`; the local binary repository was `local-repo/`. These are workstation paths and are not repository paths.
