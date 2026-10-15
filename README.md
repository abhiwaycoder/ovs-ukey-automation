# OVS Stale UKEY Automation

Automation for reproducing and verifying Open vSwitch stale UKEY cleanup.

## Reproduction

Run on Compute1:

    ./scripts/reproduce_stale_ukey.sh
    pytest -v

The reproduction:

1. Generates deterministic IPv6 multicast traffic.
2. Creates a datapath flow and UKEY.
3. Deletes the datapath flow.
4. Leaves the UKEY stale.
5. Waits for four consecutive missed revalidator dumps.
6. Verifies missed_dumps=1..4.
7. Verifies the datapath delete attempt.
8. Verifies revalidate_missing_dp_flow.
9. Verifies the UKEY is removed.
10. Saves evidence under evidence/.

## Regression Validation: Stale UKEY Cleanup

### Objective

Validate the fix for stale userspace datapath flow keys (UKEYs) by running the same Open vSwitch regression test against the baseline and patched source trees.

**Fix commit:** `ce789d991f748d95a34355e7813ddf18a64de504`

Commit message: `ofproto-dpif-upcall: Avoid stale ukeys leaks.`

### Test Details

| Property | Value |
|---|---|
| Test ID | `1315` |
| Test name | `ofproto-dpif - Cleanup missing datapath flows` |
| Test file | `tests/ofproto-dpif.at` |
| Baseline commit | `fecbba4bc01db774cb8a95b0e071eb37f16fa9f9` |
| Patched commit | `ce789d991f748d95a34355e7813ddf18a64de504` |

### Validation Results

| Check | Baseline | Patched |
|---|---|---|
| Test exit code | `1` | `0` |
| Regression test | Failed | Passed |
| Expected outcome | Regression reproduced | Regression test passed |

The baseline run failed at `ofproto-dpif.at:11970`, where the test checks that no UKEYs remain after the datapath flows have been deleted. The patched run completed successfully, with one successful test.

### What the Regression Test Verifies

The test exercises the following sequence:

1. Starts the test OVS environment and configures the required ports.
2. Generates traffic to create a datapath flow and its corresponding UKEY.
3. Verifies that a UKEY exists.
4. Deletes the datapath flows and checks that the datapath flow table is empty.
5. Advances simulated time to allow revalidator rounds to process the missing datapath flow.
6. Verifies that no UKEY keys remain.
7. Checks that the `revalidate_missing_dp_flow` coverage counter was incremented.

The baseline failure and patched success provide evidence that the fix addresses the regression exercised by this test.

### Evidence and Integrity Checks

The regression evidence is published in the repository:

- [Regression validation summary](evidence/stale-ukey-regression-summary.txt)
- [Patched regression test log](evidence/stale-ukey-test-1315-patched.log)
- [SHA-256 checksums](evidence/stale-ukey-regression-SHA256SUMS)

To verify the checksums from the repository root, run:

```bash
sha256sum -c evidence/stale-ukey-regression-SHA256SUMS
```

### Automated Validation

Repeat the baseline-versus-patched comparison using:

```bash
./scripts/validate_stale_ukey_fix.sh
```

The script checks the source trees and expected commit relationship, executes the regression test, records exit codes and logs, generates a summary, and calculates SHA-256 checksums.

The default configuration expects the baseline and patched trees under `/root/ovs-upstream-review`. See the script's usage output for supported overrides.

### Scope and Limitations

**Validation status: PASS for regression test 1315.**

This result demonstrates that the tested regression fails on the baseline and passes with the specified fix. It does not prove that every stale UKEY scenario is resolved, that all datapath cleanup paths are covered, or that the fix has been validated across every supported OVS configuration.

Broader validation should include additional relevant regression tests and runtime scenarios as appropriate.

Run this validation only in a suitable test environment. Do not use production OVS sockets, databases, or services for destructive regression testing.

## Project flow

Deterministic reproduction -> Automated verification -> GitHub Actions -> CI -> OpenStack -> End-to-end validation

## Self-hosted GitHub Actions runner

The workflow requires a self-hosted runner labelled `self-hosted` and
`ovs-ukey`. The configured runner needs the OVS build, disposable runtime,
Python 3, pip, and the `gha-runner` account.

The workflow invokes `/usr/local/sbin/ovs-ukey-ci` through sudo. The current
sudoers policy allows the runner to invoke that specific entry point:

`gha-runner ALL=(root) NOPASSWD: /usr/local/sbin/ovs-ukey-ci`

That entry point delegates to `/usr/local/libexec/ovs-ukey-reproduce`.
The reproduction script uses absolute paths specific to Compute1, so those
paths and prerequisites must be provisioned before using another runner.

## Safety

Use only the configured disposable runtime. Do not point the script at
production OVS sockets or databases, and do not restart production OVS
services as part of this test.

## Python dependencies

Install the test dependency with:

`python3 -m pip install -r requirements.txt`

---

## FastAPI Portal

The FastAPI portal submits OVS stale-UKEY automation requests through GitHub Actions.

### Features
- Web form for source RPM URL and patch input.
- Validates request inputs and supports a patch URL or patch content.
- Dispatches the `ovs-ukey-build` repository event.
- Provides a request-status endpoint.
- Includes automated portal API tests.

### Architecture

Browser -> FastAPI -> GitHub repository_dispatch -> OVS Portal Request workflow -> Input validation

**Current limitation:** The portal workflow validates inputs only. It does not yet download source RPMs, apply patches, build RPMs, or execute stale-UKEY reproduction. The existing self-hosted reproduction workflow remains separate.

Portal dispatch and workflow validation were tested successfully, and the local test suite passed 10 tests during verification.

### Configuration

Install dependencies:

    python3 -m venv .venv
    . .venv/bin/activate
    python -m pip install -r requirements.txt

Configure a local `.env` file with a fine-grained token restricted to `abhiwaycoder/ovs-ukey-automation`:

    GITHUB_TOKEN=<your-token>
    GITHUB_OWNER=abhiwaycoder
    GITHUB_REPO=ovs-ukey-automation

Use `chmod 600 .env`. Never commit or disclose the token. Load these variables into the service process before starting the portal.

### Start the portal

    .venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000

Open `http://127.0.0.1:8000/`. The health endpoint is `/health`, and interactive API documentation is available at `/docs`.

### API endpoints

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `/` | Portal web form |
| GET | `/health` | Health check |
| POST | `/build` | Validate and dispatch a request |
| GET | `/build/{request_id}` | Query workflow status |

The `/build` endpoint currently dispatches a validation request; it does not build an RPM.

### Tests

    .venv/bin/python -m pytest -v

Passing local tests does not replace validation on the configured disposable OVS test runtime.

### Portal safety
- Use only the configured disposable runtime for reproduction.
- Never point scripts at production OVS sockets or databases.
- Do not restart production OVS services as part of testing.
- Do not submit real build requests until build execution and its safety controls are implemented and reviewed.
- Keep credentials out of version control and preserve existing backup files.
