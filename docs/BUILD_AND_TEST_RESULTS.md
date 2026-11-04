# OVS 2.17.0 stale-UKEY RPM build and validation

**Build target:** EL8.10-compatible RPM build environment (Rocky Linux 8.10 container)  
**Package source version:** OVS 2.17.0  
**OVS reported software version:** 2.17.8  
**Spec release:** 106%{?dist}  
**Patch commit:** `ce789d991f748d95a34355e7813ddf18a64de504`  
**Patch file:** `openvswitch-2.17.0-stale-ukey.patch`  
**Patch SHA-256:** `454abe3e7f6f48ba7543a6c5b636129f9d6e56422a15e7fc06f0215d4ffce4cc`

## Change summary

The stale-UKEY fix tracks consecutive revalidator dumps in which a userspace flow is absent from the datapath. The `missed_dumps` counter is reset when the flow is observed again; after four consecutive misses, stale UKEY state is cleaned up. The change also increments the `revalidate_missing_dp_flow` coverage counter.

## Regression test

The focused regression test passed in the EL8.10 build container:

| Item | Result |
|---|---|
| Autotest ID | `1305` |
| Source test | `tests/ofproto-dpif.at:11842` |
| Test name | `Cleanup missing datapath flows` |
| Result | **PASS** |
| Exit code | `0` |

The test exercises a dummy datapath/bridge, creates flow/UKEY state, removes the datapath flow, advances OVS test time, verifies stale UKEY cleanup, and checks `revalidate_missing_dp_flow`.

## Additional tests

After installing the OpenSSL executable in the test container, these previously failing certificate-related tests passed on isolated rerun:

| Test ID | Description | Result |
|---|---|---|
| 2281 | `ovsdb-server/rbac 2` | PASS |
| 2327 | `bootstrap ca cert` | PASS |
| 2328 | `peer ca cert` | PASS |

## Historical local full-suite attempt (October 30, 2026)

A serial full-suite run (`make check TESTSUITEFLAGS="-j1"`) executed 2,434
tests, with 3 skipped and 4 unexpected failures at that time. Three of those
failures were certificate-related tests (2281, 2327, and 2328); they passed
on isolated rerun after installing the OpenSSL executable in the test
container.

The remaining failure was test 1996, `monitor-cond-change with many sessions
pending` (`tests/ovsdb-monitor.at:594`). Its isolated rerun also failed.
Host kernel OOM records from that period showed global memory pressure and
OOM-killer activity, including termination of an `ovsdb-server` process.
This was recorded as a resource-constrained unresolved failure in that
initial local attempt. This historical result is superseded for the current
RPM validation status by the later complete hosted `%check` run below; it is
retained here as a record of the earlier troubleshooting.

## Latest hosted RPM `%check` result (November 3, 2026)

The separate **OVS RPM Build with Tests** workflow rebuilt the package from
the clean EL8S source RPM and the verified stale-UKEY patch in a Rocky Linux
8.10 container. The workflow ran `scripts/build_rpm.sh` with
`--with-check` and one build job.

- Workflow run: [41572770829 — OVS RPM Build with Tests](https://github.com/abhiwaycoder/ovs-ukey-automation/actions/runs/41572770829)
- Workflow run number: 7
- Job: `rpm-check`
- Result: **success**; all workflow steps completed successfully.
- Full suite: **2,436 passed, 1 skipped**.
- Targeted test: **1305 — Cleanup missing datapath flows — PASS**.
- RPM outputs: 9 binary RPMs and 1 source RPM.
- RPM digest verification and artifact upload completed.

The run's artifact is `ovs-rpm-check-validation-41572770829`
(artifact ID `13204797978`). The workflow uses GitHub-hosted infrastructure,
a Rocky Linux 8.10 container with Docker `--init`, and a serial RPM build.
Its job summary explicitly records that kernel datapath tests were not
enabled; this is userspace RPM `%check` validation.

**Test ID distinction:** test 1305 is the targeted test reported by this
November 3 RPM `%check` run. Test 1315 in the separate
[historical baseline-versus-patched validation report](OVS-STALE-UKEY-VALIDATION.md)
is a distinct earlier test record. Do not substitute one ID for the other.

The November 3 checked build is separate from the November 2 RPM release
assets produced with `--nocheck`. It proves that a later build of the same
package version completed `%check`; it does not retroactively change the
provenance of previously published no-check RPM assets.

## Manual runtime validation (November 3, 2026)

Three consecutive manual runtime cleanup cycles passed using
`openvswitch2.17-2.17.0-106.el8.x86_64`.

| Runtime check | Each cycle |
|---|---:|
| UKEYs before datapath-flow deletion | 2 |
| Datapath flows before deletion | 2 |
| UKEYs after revalidation | 0 |
| Datapath flows after cleanup | 0 |
| Expected `flow_del` ENOENT warnings | 2 |

Environment:
- OVS userspace package built for EL8.10 in Rocky Linux 8.10.
- Runtime host kernel: RHEL 9.8,
  `5.14.0-687.30.1.el9_8.x86_64`.
- Isolated container network namespace with a private OVS system datapath,
  two peer network namespaces, and veth connectivity.

Evidence, per-cycle snapshots and logs, the summary, and SHA-256 manifests
are committed under
[validation/ovs-2.17.8-stale-ukey-runtime-validation/](../validation/ovs-2.17.8-stale-ukey-runtime-validation/).

**Scope limitation:** this demonstrates cleanup with EL8.10-built OVS
userspace against a RHEL 9.8 host kernel. It is not native EL8 kernel
validation. The manual runtime test confirms cleanup to zero but does not
independently instrument or measure the four-consecutive-missed-dump
threshold. The automated self-hosted runtime reproduction remains a
separate validation task.

## RPM build result

The RPM build completed successfully in the EL8.10-compatible Rocky Linux 8.10 container on 2026-10-30. The command used `rpmbuild --nocheck -ba SPECS/openvswitch2.17.spec`; therefore, the RPM build stages completed, but the spec's `%check` tests were explicitly skipped.

- Package NEVRA: `openvswitch2.17-2.17.0-106.el8.x86_64`
- Build host: `7eb24923af24` (container hostname)
- Build date: 2026-10-30 20:39:58 UTC
- Binary RPMs: 9
- Source RPMs: 1
- RPM signature: none (unsigned)
- RPM integrity: `rpm -K` reported `digests OK` for all 10 RPM files

This is a successful package build with `%check` skipped. It is **not** a claim that the complete test suite or RPM `%check` passed.

### Generated RPM artifacts

| Package | Architecture | Size (bytes) |
|---|---:|---:|
| `openvswitch2.17` | x86_64 | 6,828,948 |
| `python3-openvswitch2.17` | x86_64 | 314,328 |
| `openvswitch2.17-devel` | x86_64 | 221,016 |
| `network-scripts-openvswitch2.17` | x86_64 | 90,996 |
| `openvswitch2.17-ipsec` | x86_64 | 99,376 |
| `openvswitch2.17-debugsource` | x86_64 | 7,022,236 |
| `openvswitch2.17-debuginfo` | x86_64 | 29,141,452 |
| `python3-openvswitch2.17-debuginfo` | x86_64 | 104,632 |
| `openvswitch2.17-test` | noarch | 137,392 |
| `openvswitch2.17` source package | src | 31,710,916 |

### SHA-256 checksums

The following values were calculated from the generated RPM files. All ten files passed `rpm -K` digest verification.

```text
f66a082faffdafb38cbaa422158a04c49d473a67cb8917c91318ac7c838ece4d  openvswitch2.17-2.17.0-106.el8.x86_64.rpm
7e51affc22772a5dbde15c15cf736132594c2642178d240a7049c50c5d2ff8fa  python3-openvswitch2.17-2.17.0-106.el8.x86_64.rpm
caf9e1b80de0ab98e604cad867ba9aa1348c0365c480437c7fb75a4e0b22364c  openvswitch2.17-devel-2.17.0-106.el8.x86_64.rpm
8f4881ab60079894b869496c275c1884e7b246264f350d5447b7d1d4407e8cbd  network-scripts-openvswitch2.17-2.17.0-106.el8.x86_64.rpm
6382821ed4123e918bf0c5a5436592f43e7a763a8af3679721b514368ee6efbf  openvswitch2.17-ipsec-2.17.0-106.el8.x86_64.rpm
4a44f3451a4f021d2689c3ce0dbbb57310bb2230c13d0c7fd10720b3dc9ffe5d  openvswitch2.17-debugsource-2.17.0-106.el8.x86_64.rpm
97d79d224ac47e4cb6d502b920f16ed6d67773d6a433a462483fa020faba6b6a  openvswitch2.17-debuginfo-2.17.0-106.el8.x86_64.rpm
b234e31c86107b814524aaa410790feb5a6cefe54096670031c69544d7ecd46b  python3-openvswitch2.17-debuginfo-2.17.0-106.el8.x86_64.rpm
d3da63cb67e7b69444ccc385fc1df076d1558bb8103f1e3014db620aaf257e19  openvswitch2.17-test-2.17.0-106.el8.noarch.rpm
64307587bde2a4e0b8b273aa5b976fc851f9b36cd285b5846288715b4ab589cc  openvswitch2.17-2.17.0-106.el8.src.rpm
```

A copy of the checksum list is maintained in [evidence/el8.10-rpm-SHA256SUMS](../evidence/el8.10-rpm-SHA256SUMS).

## Manual RPM signing and local repository validation (November 3, 2026)

The November 3 checked-build artifact was separately signed on a protected
workstation after download and verification of its original `SHA256SUMS`
manifest.

Source artifact:
- [Workflow run 41572770829](https://github.com/abhiwaycoder/ovs-ukey-automation/actions/runs/41572770829), run number 7.
- Artifact: `ovs-rpm-check-validation-41572770829`, ID `13204797978`.
- Build commit: `83a4095f614adac7d9eaa1ff847151695515bfa2`.
- Artifact archive digest: `sha256:c2d50eca085363376cf94ced4f10ec625c057b194959511223ddc0eae6cc074a`.
- Contents: 9 binary RPMs and 1 source RPM.
- Original artifact SHA-256 manifest: all ten entries passed before signing.

Signing key:
- User ID: `OVS Stale UKEY RPM Signing`.
- RSA 4096; created November 3, 2026; expires November 2, 2028.
- Full fingerprint: `7F34141A60E9B91DABF3978DFEC22E62BB0AD5CB`.
- RPM signature observed: OpenPGP V4 RSA/SHA512.

All 9 binary RPMs and the 1 source RPM were signed into a separate output
directory, leaving the original downloaded RPMs unchanged. Each signed
package passed verification against an isolated RPM database containing the
project public key:
- Header OpenPGP signature: 10/10 PASS.
- Header SHA-256 digest: 10/10 PASS.
- Payload SHA-256 digest: 10/10 PASS.
- Original, pre-signing SHA-256 manifest: 10/10 PASS after signing.

The signed package SHA-256 checksums are recorded in
[evidence/rpm-signing-validation-20261103.md](../evidence/rpm-signing-validation-20261103.md).

### Local DNF repository test

A local binary repository was assembled from the nine signed binary RPMs.
The source RPM remained separately available in the signed output. Repository
metadata was generated with `createrepo_c --checksum sha256`; a detached
ASCII-armored signature was generated for `repodata/repomd.xml` and GPG
reported a good signature from the project key.

The local repository SHA-256 manifest covered 15 files and all entries passed.
DNF5 was configured with `gpgcheck=1`, `pkg_gpgcheck=1`, and
`repo_gpgcheck=1`:
- `makecache --refresh`: PASS; repository metadata authenticated.
- `list --available`: all 9 binary packages listed.
- `reposync --gpgcheck`: all 9 packages downloaded.
- Independent RPM signature and digest verification of the 9 downloaded
  packages: PASS.

This is local repository and download validation, not an installation test.
The exported public key is included at
[`keys/RPM-GPG-KEY-OVS-STALE-UKEY`](../keys/RPM-GPG-KEY-OVS-STALE-UKEY),
with fingerprint `7F34141A60E9B91DABF3978DFEC22E62BB0AD5CB`. Verify the
fingerprint through an independently authenticated channel before trusting
packages. The signed RPMs and local repository have not yet been published as
GitHub Release assets or hosted repository content. The November 2
`--nocheck` release assets remain separate, unsigned artifacts; this manual
signing run does not change their provenance.

No package installation, upgrade, rollback, OVS service restart, or OpenStack
end-to-end validation was performed in the November 3 signing phase. A
subsequent separate native RHEL 8.10 test completed a same-NEVRA signed-package
replacement, explicit OVS service restart, and runtime UKEY cleanup check.
A different-NEVRA upgrade and rollback remain pending; see the
[native EL8 runtime validation report](../validation/ovs-2.17.8-rhel8-native-runtime-validation/README.md).

## Remaining validation and release work

The full hosted RPM `%check` suite and the separate manual RPM signing/local
repository verification have now passed. Remaining work is:

1. Publish the signed RPM copies and repository metadata/checksums as a
   release artifact or hosted repository. The exported public key is included
   at [`keys/RPM-GPG-KEY-OVS-STALE-UKEY`](../keys/RPM-GPG-KEY-OVS-STALE-UKEY);
   verify its full fingerprint through an independently authenticated channel.
2. Complete a different-NEVRA native EL8 upgrade and rollback test.
   The same-NEVRA signed-package replacement, service restart, and runtime
   cleanup check have been completed on the disposable RHEL 8.10 VM; see
   the native EL8 runtime validation report.
3. Restore the isolated self-hosted runtime runner only after verifying host
   memory headroom and OpenStack workload safety, then run
   `.github/workflows/runtime-reproduction.yml` and capture the
   `missed_dumps=1..4` and `revalidate_missing_dp_flow` evidence.
4. Complete OpenStack integration and end-to-end network validation.

The November 2 release assets remain `--nocheck` artifacts. Do not describe
those particular files as having passed `%check`; use the separate
November 3 checked-build artifact when referring to the successful
`%check` run.

## Integrity

Patch SHA-256:

```
454abe3e7f6f48ba7543a6c5b636129f9d6e56422a15e7fc06f0215d4ffce4cc  openvswitch-2.17.0-stale-ukey.patch
```
