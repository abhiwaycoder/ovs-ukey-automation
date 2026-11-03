# OVS Stale UKEY Cleanup — Validation Report

## 1. Overview

This report records the regression validation performed for the
Open vSwitch stale UKEY cleanup fix.

- **Fix commit:** `ce789d991f748d95a34355e7813ddf18a64de504`
- **Fix description:** `ofproto-dpif-upcall: Avoid stale ukeys leaks.`
- **Regression test:** `ofproto-dpif - Cleanup missing datapath flows`
- **Test ID:** 1315
- **Test source:** `tests/ofproto-dpif.at`

## 2. Historical baseline-versus-patched regression results (test 1315)

| Validation | Result |
|---|---|
| Baseline test | Failed at the expected regression assertion |
| Patched test | Passed with exit code 0 |
| Local Python test suite | 21 tests passed |
| GitHub Actions run #21 | Successful |
| Evidence checksum verification | Passed |

The baseline-versus-patched test supports the conclusion that the
fix addresses the stale UKEY regression exercised by test 1315.

This is the earlier historical regression comparison. The later November 3
hosted RPM `%check` run reported targeted test 1305 as passed. Test IDs 1315
and 1305 refer to separate recorded test executions and are not interchangeable.

## 3. Python Test Suite

The project's virtual environment was used to execute:

```bash
.venv/bin/python -m pytest -v
```

Result: **21 passed**.

The tests cover the portal API, workflow status handling, and
stale UKEY evidence validation.

## 4. Continuous Integration

- **Workflow:** OVS UKEY Tests
- **Run:** #21
- **Commit:** `1bf9749`
- **Result:** Success
- **Duration shown by GitHub:** 27 seconds

Workflow history:
https://github.com/abhiwaycoder/ovs-ukey-automation/actions

The run confirms that the configured GitHub Actions job succeeded
for commit `1bf9749`.

## 5. Regression Evidence

The following evidence files are maintained in the repository:

- `evidence/stale-ukey-regression-summary.txt`
- `evidence/stale-ukey-test-1315-patched.log`
- `evidence/stale-ukey-regression-SHA256SUMS`

The SHA-256 manifest was checked with:

```bash
sha256sum -c evidence/stale-ukey-regression-SHA256SUMS
```

Both listed evidence files passed checksum verification.

## 6. Scope and Limitations

These results support the fix for the regression scenario covered by
test 1315. They do not prove that every possible stale UKEY cleanup
scenario has been tested or that all cleanup paths are covered.

The successful Python suite and GitHub Actions result should not be
interpreted as broader proof beyond the tests and checks actually run.

## 7. References

- Repository: https://github.com/abhiwaycoder/ovs-ukey-automation
- Workflow runs: https://github.com/abhiwaycoder/ovs-ukey-automation/actions
- Regression summary: `evidence/stale-ukey-regression-summary.txt`
- Patched test log: `evidence/stale-ukey-test-1315-patched.log`

## 8. Later hosted RPM `%check` and runtime validation (November 3, 2026)

### RPM `%check`

A separate Rocky Linux 8.10 GitHub Actions workflow rebuilt the RPMs with
`--with-check` and completed successfully.

- Workflow: [OVS RPM Build with Tests, run 41572770829](https://github.com/abhiwaycoder/ovs-ukey-automation/actions/runs/41572770829)
- Result: **success**.
- Full suite: **2,436 passed, 1 skipped**.
- Targeted test: **1305 — Cleanup missing datapath flows — PASS**.
- Outputs: 9 binary RPMs and 1 source RPM.
- Artifact: `ovs-rpm-check-validation-41572770829`
  (ID `13204797978`).

This was a subsequent checked build. It does not change the provenance of
the earlier November 2 release assets, which were produced using
`--nocheck`. The workflow did not enable kernel datapath tests.

### Manual runtime cleanup

Three consecutive manual runtime cycles passed. Each cycle began with
2 UKEYs and 2 datapath flows; after datapath-flow deletion and revalidation,
both counts reached zero. Two expected `flow_del (No such file or directory)`
warnings were recorded per cycle.

The package userspace was built for EL8.10 in Rocky Linux 8.10. Runtime
validation used the RHEL 9.8 host kernel
`5.14.0-687.30.1.el9_8.x86_64` in an isolated container network namespace
with a private OVS datapath and two peer network namespaces connected by
veth pairs.

The complete evidence is committed under
[validation/ovs-2.17.8-stale-ukey-runtime-validation/](../validation/ovs-2.17.8-stale-ukey-runtime-validation),
including the per-cycle before/after snapshots, ping and deletion logs,
summary, and SHA-256 manifests.

### Scope and remaining work

The manual runtime result confirms stale UKEY cleanup in this isolated setup.
It is not native EL8 kernel validation and does not independently measure
the instrumented four-consecutive-missed-dump threshold. Automated runtime
reproduction on a healthy isolated self-hosted runner, native target-kernel
validation where required, RPM signing and repository publication,
installation/upgrade testing, and OpenStack end-to-end validation remain
separate tasks.

