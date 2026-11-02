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

Deterministic reproduction -> Regression verification -> Hosted RPM build -> RPM artifact -> OpenStack -> End-to-end validation

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

## FastAPI Portal and hosted RPM build

The FastAPI portal submits OVS RPM build requests through GitHub Actions.

### Features

- Web form prefilled with the clean EL8 source RPM and tested stale-UKEY patch URLs.
- Supports the published patch URL or patch content.
- Dispatches the `ovs-ukey-build` repository event with a request UUID.
- Builds in a GitHub-hosted runner using a Rocky Linux 8.10 container.
- Uploads 9 binary RPMs, 1 source RPM, the build log, and SHA-256 manifest as a workflow artifact.
- Provides a request-status endpoint that locates the matching workflow run.

### Build inputs

The clean base SRPM is the CentOS Stream 8 NFV archive package
`openvswitch2.17-2.17.0-106.el8s.src.rpm` from the CentOS Vault snapshot.
The workflow checks its published size (31,709,062 bytes) and RPM
name/version/release before building.

The tested stale-UKEY patch is distributed as a GitHub Release asset.
The workflow verifies the patch SHA-256 against the hash used in the successful
local build:

`454abe3e7f6f48ba7543a6c5b636129f9d6e56422a15e7fc06f0215d4ffce4cc`

The Release asset must be created at tag
`ovs-2.17.0-106.el8-build-inputs` with the filename
`openvswitch-2.17.0-stale-ukey.patch`. Until that asset is uploaded, the
hosted build workflow cannot complete its input validation.

### Architecture

Browser -> FastAPI -> GitHub repository_dispatch -> OVS Portal RPM Build -> Rocky Linux 8.10 container -> RPM artifacts

### Workflow behavior and limits

The workflow installs BuildRequires from the clean SRPM, applies the vendor
patch and stale-UKEY patch through the spec, builds with one job and
`--nocheck`, verifies RPM digests, and uploads the resulting artifacts.

The `%check` stage is skipped. The workflow does not sign RPMs, publish a
package repository, install OVS, or run the datapath reproduction. Signing,
deployment, and OpenStack runtime validation remain separate steps.

The runtime reproduction workflow is separate and still requires a healthy,
resource-appropriate self-hosted runner. The OOM-affected Compute1 runner is
not used for hosted RPM building.

### Configuration

Install portal dependencies:

    python3 -m venv .venv
    . .venv/bin/activate
    python -m pip install -r requirements.txt

Configure a local `.env` file with a fine-grained token restricted to
`abhiwaycoder/ovs-ukey-automation` and permission to create repository
dispatch events:

    GITHUB_TOKEN=<your-token>
    GITHUB_OWNER=abhiwaycoder
    GITHUB_REPO=ovs-ukey-automation

Use `chmod 600 .env`. Never commit or disclose the token. Load these
variables into the service process before starting the portal.

### Start the portal

    .venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000

Open `http://127.0.0.1:8000/`. The health endpoint is `/health`, and
interactive API documentation is available at `/docs`.

### API endpoints

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `/` | Portal web form |
| GET | `/health` | Health check |
| POST | `/build` | Dispatch an RPM build request |
| GET | `/build/{request_id}` | Query the matching GitHub Actions run |

### Tests

    .venv/bin/python -m pytest -v

Passing local tests does not replace validation on the configured disposable
OVS runtime.

### Portal safety

- The hosted builder only builds packages; it does not install or start OVS.
- Never point reproduction scripts at production OVS sockets or databases.
- Keep credentials out of version control.
- Use only the validated source RPM and tested stale-UKEY patch inputs.

---

## OVS RPM build and test report

The EL8.10 package build and validation status, including the focused regression result and the unresolved full-suite resource failure, are documented in [docs/BUILD_AND_TEST_RESULTS.md](docs/BUILD_AND_TEST_RESULTS.md).

**Package status:** Nine binary RPMs and one source RPM were generated successfully for `2.17.0-106.el8`. The build used `rpmbuild --nocheck`, so the RPM `%check` stage was skipped and is not claimed as passed. All ten RPM files passed `rpm -K` digest verification. SHA-256 values are recorded in [evidence/el8.10-rpm-SHA256SUMS](evidence/el8.10-rpm-SHA256SUMS). The RPMs are unsigned.

### Repeatable RPM build script

A parameterized build script is now available at [scripts/build_rpm.sh](scripts/build_rpm.sh). It starts from a clean source RPM, adds the stale-UKEY patch as `Patch1`, builds in a separate top directory, verifies RPM digests, and generates a checksum manifest. See [docs/REPEATABLE_RPM_BUILD.md](docs/REPEATABLE_RPM_BUILD.md) for prerequisites and usage.

The script defaults to one build job and skips `%check`; add `--with-check` to run it. It does not download inputs, sign RPMs, install packages, or run the OVS reproduction.


### Build script validation evidence

The repository build script has been executed successfully in the Rocky Linux 8.10 container. It generated nine binary RPMs and one source RPM; all ten passed `rpm -K` digest checks. The run used the default `--nocheck` mode, so it does not establish a passing `%check` suite. See [the script validation report](evidence/repeatable-rpm-build-validation.md).
