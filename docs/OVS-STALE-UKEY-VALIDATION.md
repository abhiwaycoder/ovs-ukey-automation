# OVS Stale UKEY Cleanup — Validation Report

## 1. Overview

This report records the regression validation performed for the
Open vSwitch stale UKEY cleanup fix.

- **Fix commit:** `ce789d991f748d95a34355e7813ddf18a64de504`
- **Fix description:** `ofproto-dpif-upcall: Avoid stale ukeys leaks.`
- **Regression test:** `ofproto-dpif - Cleanup missing datapath flows`
- **Test ID:** 1315
- **Test source:** `tests/ofproto-dpif.at`

## 2. Regression Test Results

| Validation | Result |
|---|---|
| Baseline test | Failed at the expected regression assertion |
| Patched test | Passed with exit code 0 |
| Local Python test suite | 21 tests passed |
| GitHub Actions run #21 | Successful |
| Evidence checksum verification | Passed |

The baseline-versus-patched test supports the conclusion that the
fix addresses the stale UKEY regression exercised by test 1315.

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
