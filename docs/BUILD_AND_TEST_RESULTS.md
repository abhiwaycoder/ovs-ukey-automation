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

## Full test suite status

A serial full-suite run (`make check TESTSUITEFLAGS="-j1"`) executed 2,434 tests, with 3 skipped and 4 unexpected failures at that time. Three of those failures were the certificate-related tests listed above and passed when rerun after OpenSSL was installed.

The remaining failure was test 1996, `monitor-cond-change with many sessions pending` (`tests/ovsdb-monitor.at:594`). Its isolated rerun also failed. Host kernel OOM records from the test period show global memory pressure and OOM-killer activity, including termination of an `ovsdb-server` process. This stress-test failure is therefore recorded as **resource-constrained / unresolved**, not as a passing test and not as evidence of a stale-UKEY patch regression.

The complete suite has **not** been rerun after the OpenSSL installation. Consequently, this report does not claim a clean full-suite result or a successful RPM `%check` stage.

## RPM artifact status

The inventory checked on 2026-10-30 found no binary RPM or source RPM in the configured `RPMS/` and `SRPMS/` output directories. The original RPM build reached `%check` and exited with a failure. A package must still be generated.

If a package is subsequently built with `rpmbuild --nocheck`, it must be labelled as a build with `%check` skipped. That package must not be represented as having passed the complete RPM validation suite.

## Recommended next validation

Repeat the complete serial `%check` on a host with sufficient available memory and low competing workload. Then run the full RPM build with checks enabled and record the final suite summary, RPM metadata, file size, and SHA-256 checksum.

## Integrity

Patch SHA-256:

```
454abe3e7f6f48ba7543a6c5b636129f9d6e56422a15e7fc06f0215d4ffce4cc  openvswitch-2.17.0-stale-ukey.patch
```
