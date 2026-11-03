# OVS Stale UKEY Automation

Automation for reproducing and verifying Open vSwitch stale UKEY cleanup.


## Latest validation status — November 3, 2026

The latest RPM validation completed successfully in the Rocky Linux 8.10 build container:

- RPM `%check` completed successfully.
- **2,436 tests passed and 1 test was skipped.**
- Targeted test **1305**, `Cleanup missing datapath flows`, passed.
- The workflow generated 9 binary RPMs and 1 source RPM.
- Three manual runtime cleanup cycles passed: each began with 2 UKEYs and 2 datapath flows and ended with 0 UKEYs and 0 datapath flows.

The runtime test used the EL8.10-built OVS userspace against the RHEL 9.8 host kernel (`5.14.0-687.30.1.el9_8.x86_64`) inside an isolated container network namespace. It is **not native EL8 kernel validation** and does not independently measure the four-missed-dump threshold.

- [RPM `%check` validation report](evidence/rpm-check-validation-41572770829.md)
- [RPM signing and local DNF repository validation](evidence/rpm-signing-validation-20261103.md)
- [Runtime evidence directory](validation/ovs-2.17.8-stale-ukey-runtime-validation/)
- [RPM build and test workflow](https://github.com/abhiwaycoder/ovs-ukey-automation/actions/runs/41572770829)

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

**Historical validation status: PASS for regression test 1315.**

This is the earlier baseline-versus-patched regression record. It is separate from the later RPM `%check` run, which reported targeted test 1305 as passed. These are distinct test records and their IDs should not be treated as interchangeable.

This result demonstrates that the tested regression fails on the baseline and passes with the specified fix. It does not prove that every stale UKEY scenario is resolved, that all datapath cleanup paths are covered, or that the fix has been validated across every supported OVS configuration.

Broader validation should include additional relevant regression tests and runtime scenarios as appropriate.

Run this validation only in a suitable test environment. Do not use production OVS sockets, databases, or services for destructive regression testing.

## Project flow

Deterministic reproduction -> Regression verification -> Hosted RPM build -> RPM artifact -> OpenStack -> End-to-end validation

## Runtime reproduction runner

The regular pull-request unit tests run on GitHub-hosted infrastructure and
use the committed evidence fixtures in `tests/fixtures/evidence`.

The real datapath reproduction remains separate in
`.github/workflows/runtime-reproduction.yml`. It is a manual workflow and
requires a self-hosted runner labelled `self-hosted` and `ovs-ukey`. That
runner needs the disposable OVS runtime, Python 3, pip, and the
`gha-runner` account.

The workflow invokes `/usr/local/sbin/ovs-ukey-ci` through sudo. The current
sudoers policy allows that specific entry point:

`gha-runner ALL=(root) NOPASSWD: /usr/local/sbin/ovs-ukey-ci`

The entry point delegates to `/usr/local/libexec/ovs-ukey-reproduce`, whose
paths are specific to Compute1.

A separate manual runtime validation was completed on November 3, 2026 in an
isolated container network namespace. Three consecutive cycles each showed
2 UKEYs / 2 datapath flows before datapath-flow deletion and 0 UKEYs / 0 flows
after revalidation. See
[the committed runtime evidence](validation/ovs-2.17.8-stale-ukey-runtime-validation/).
This manual test confirms cleanup in that setup; it does not replace the
self-hosted workflow's checks of `missed_dumps=1..4` and the
`revalidate_missing_dp_flow` coverage counter.

**Resource warning:** the Compute1 self-hosted runner previously failed after
a host-wide OOM event. It is not used for RPM builds or automatic pull-request
tests. Do not restart it until host memory pressure and OpenStack workload
capacity have been addressed.

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

The Release asset is published at tag
`ovs-2.17.0-106.el8-build-inputs` with the filename
`openvswitch-2.17.0-stale-ukey.patch`. Its SHA-256 is checked by the hosted
workflow before the build starts.

### Architecture

Browser -> FastAPI -> GitHub repository_dispatch -> OVS Portal RPM Build -> Rocky Linux 8.10 container -> RPM artifacts

### Hosted RPM build result

The first complete GitHub-hosted Rocky Linux 8.10 RPM build passed on
November 2, 2026: [workflow run 41386001794](https://github.com/abhiwaycoder/ovs-ukey-automation/actions/runs/41386001794).
It generated nine binary RPMs and one source RPM, passed `rpm -K` digest
verification for all ten packages, and uploaded the RPMs, build log, and
SHA-256 manifest as artifact `ovs-rpm-build-41386001794`. The ZIP artifact
SHA-256 is
`aff18e70c5bdd1f2eba75134b8aa4759e92aa25a3ca97de787935837fdd04a3a`.
The artifact is retained for 14 days. See
[evidence/hosted-rpm-build-41386001794.md](evidence/hosted-rpm-build-41386001794.md)
for the run details and generated package checksums.

This November 2 build used `--nocheck`; it did not execute the RPM spec
`%check` suite. Those specific release assets remain no-check, unsigned
artifacts. A separate November 3 workflow rebuilt the RPMs with
`--with-check` and completed the spec test suite successfully; see the
[RPM `%check` validation report](evidence/rpm-check-validation-41572770829.md).

On November 3, a separate manual release-signing operation downloaded the
checked-build artifact from workflow run 41572770829, verified its original
checksums, and signed all 9 binary RPMs plus the 1 source RPM with a
project-specific OpenPGP key. All ten package signatures and payload/header
digests passed independent verification. A local repository was generated,
its `repomd.xml` was signed, and DNF5 metadata and package-download checks
passed. See the [RPM signing and local repository validation report](evidence/rpm-signing-validation-20261103.md).

The signed copies and local repository have not yet been published as GitHub
Release assets or through a hosted package repository. The public key used by
the local repository has not yet been committed to this repository. The
November 3 signing operation does not retroactively change the provenance of
the November 2 no-check release assets.

### Workflow behavior and limits

The portal-dispatch workflow installs BuildRequires from the clean SRPM, applies
the vendor patch and stale-UKEY patch through the spec, and builds with one
job using `--nocheck`. It verifies RPM digests and uploads the resulting
artifacts; this workflow intentionally skips `%check`.

The separate `.github/workflows/ovs-rpm-check.yml` workflow runs the build
with `--with-check`. Its November 3, 2026 run completed successfully with
2,436 tests passed and 1 skipped, including targeted test 1305. The run
generated 9 binary RPMs and 1 source RPM. See the
[RPM `%check` report](evidence/rpm-check-validation-41572770829.md).

Neither GitHub Actions build workflow signs RPMs, publishes a package
repository, installs OVS, or performs OpenStack end-to-end validation. Manual
signing and local DNF repository validation were completed separately on
November 3, 2026; publication and EL8 installation/upgrade/rollback testing
remain pending. See the [signing validation report](evidence/rpm-signing-validation-20261103.md).

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

The package build history, successful November 3 RPM `%check` run, targeted regression result, and manual runtime evidence are documented in [docs/BUILD_AND_TEST_RESULTS.md](docs/BUILD_AND_TEST_RESULTS.md).

**Current validation status:** The November 3 hosted RPM `%check` run passed with 2,436 tests passed and 1 skipped; targeted test 1305 passed. It generated 9 binary RPMs and 1 source RPM. Three additional manual runtime cycles confirmed UKEY and datapath-flow cleanup in an isolated container network namespace. The original November 2 release RPM assets were built with `--nocheck` and remain unsigned. Separately, signed copies of the November 3 checked-build artifact were created and verified locally, with a signed local DNF repository. Those signed copies and the public key have not yet been published. See [RPM signing validation](evidence/rpm-signing-validation-20261103.md).

### Repeatable RPM build script

A parameterized build script is now available at [scripts/build_rpm.sh](scripts/build_rpm.sh). It starts from a clean source RPM, adds the stale-UKEY patch as `Patch1`, builds in a separate top directory, verifies RPM digests, and generates a checksum manifest. See [docs/REPEATABLE_RPM_BUILD.md](docs/REPEATABLE_RPM_BUILD.md) for prerequisites and usage.

The script defaults to one build job and skips `%check`; add `--with-check` to run it. It does not download inputs, sign RPMs, install packages, or run the OVS reproduction.


### Build script validation evidence

The repository build script has been executed successfully in the Rocky Linux 8.10 container. It generated nine binary RPMs and one source RPM; all ten passed `rpm -K` digest checks. The run used the default `--nocheck` mode, so it does not establish a passing `%check` suite. See [the script validation report](evidence/repeatable-rpm-build-validation.md).
