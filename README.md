# Open vSwitch Stale UKEY Fix — Build and Validation Guide

This project helps build and test an Open vSwitch (OVS) package that contains a fix for **stale UKEY cleanup**. It also provides a small web portal and GitHub Actions workflows so that a build can be requested and its results can be collected in a repeatable way.

You do not need to know OVS internals to follow this page. The first sections explain the problem and the project workflow in plain language. The later sections explain how to set up the portal and run the available checks.

> **Important:** Use only disposable test machines and isolated test networking. Never run destructive runtime tests against production OVS services, sockets, databases, or networks.

## 1. What problem is being solved?

Open vSwitch is software that helps a Linux machine or a cloud platform move network traffic between virtual machines and networks.

To make forwarding fast, OVS keeps records of network flows. A **UKEY** (userspace flow key) is an internal userspace record associated with a datapath flow. The datapath is the part that actually forwards packets.

Sometimes a datapath flow disappears but its related UKEY remains in OVS userspace. That leftover record is called a **stale UKEY**. The fix being validated makes OVS notice repeated cases where a flow is missing and clean up the stale userspace record.

In everyday terms: imagine a tracking list that still contains an item after the item has already been removed from the system. This project checks that OVS eventually removes that leftover entry instead of keeping it indefinitely.

The fix being tested is:

- **Upstream fix commit:** `ce789d991f748d95a34355e7813ddf18a64de504`
- **Commit subject:** `ofproto-dpif-upcall: Avoid stale ukeys leaks.`

The intended behavior tracks consecutive revalidator checks where a flow is missing. The counter resets if the flow is seen again. After four consecutive misses, stale UKEY cleanup is expected to happen.

## 2. What does this project provide?

The repository brings together four parts:

1. **Regression validation** — checks that the bug can be reproduced on the baseline source and that the patched source passes the relevant test.
2. **RPM packaging** — takes a clean Open vSwitch source RPM and the tested fix patch, then builds installable RPM packages.
3. **A web portal and GitHub Actions automation** — lets a user submit a build request and follow the corresponding GitHub Actions run.
4. **Runtime validation** — checks the behavior of a running OVS instance, including whether stale UKEYs are removed after datapath-flow deletion.

The project is designed to move from source-code verification to package creation and then to testing on a real, isolated runtime.

## 3. How the project workflow fits together

The web portal is the front door. GitHub Actions performs the repeatable package build. Dedicated workflows run the RPM test suite and the real runtime reproduction.

```text
User
 |
 v
FastAPI web portal
 |
 | submits a request ID and the approved build inputs
 v
GitHub repository_dispatch event
 |
 v
GitHub Actions — RPM build
 |
 | downloads clean source RPM and verified patch
 v
Rocky Linux 8.10 build container
 |
 | builds RPMs and creates checksums
 v
GitHub Actions artifact
 |
 +----> Separate RPM %check workflow
 |
 +----> RPM signing and repository integrity verification
 |
 +----> Isolated runtime validation
 |
 +----> Native RHEL 8.10 package/runtime validation
```

The workflow keeps package creation, RPM testing, package integrity checks, and runtime validation as separate, auditable stages.

## 4. Implemented and validated components

The status below reflects the evidence committed to this repository through **November 4, 2026**.

| Work area | Result | What it means |
|---|---|---|
| Baseline-versus-patched regression comparison | Completed | The historical focused test failed on the baseline and passed on the patched source. |
| Repeatable RPM build script | Completed | A clean source RPM and the tested patch can be used to create RPMs. |
| GitHub-hosted RPM build | Passed | The workflow created 9 binary RPMs and 1 source RPM. |
| RPM %check suite | Passed | 2,436 tests passed and 1 was skipped; targeted test 1305 passed. |
| Manual RPM signing | Completed locally | All 10 checked-build RPMs passed signature and digest verification on the signing workstation. |
| Local signed DNF repository | Verified locally | Repository metadata and package downloads passed signature checks. |
| Manual runtime cleanup in an isolated container namespace | Passed | Three cycles reached zero UKEYs and zero datapath flows. |
| Native RHEL 8.10 runtime check | Passed | Signed same-NEVRA package replacement and runtime cleanup were verified on a disposable RHEL 8.10 VM. |

### A few important test details

- The hosted RPM %check run on November 3, 2026 reported **2,436 passed and 1 skipped**. Targeted test **1305**, `Cleanup missing datapath flows`, passed. This is the RPM userspace test suite; it does not enable kernel datapath tests.
- The earlier baseline-versus-patched report refers to test **1315**. Test 1315 and test 1305 are separate test records. Do not treat their IDs as interchangeable.
- Three manual runtime cycles using EL8.10-built OVS userspace against a RHEL 9.8 host kernel reached zero UKEYs and zero datapath flows.
- On November 4, a separate native RHEL 8.10 VM test verified signed same-NEVRA package replacement, service activation, traffic, and eventual UKEY cleanup. The UKEY count reached zero on the fifth approximately half-second sample.

See the detailed [build and test report](docs/BUILD_AND_TEST_RESULTS.md), [RPM signing report](evidence/rpm-signing-validation-20261103.md), and [native RHEL 8.10 runtime report](validation/ovs-2.17.8-rhel8-native-runtime-validation/README.md).

## 5. Repository map

| Location | What it contains |
|---|---|
| `app/main.py` | FastAPI portal: web page, build submission, and request-status endpoint. |
| `scripts/build_rpm.sh` | Repeatable script that adds the stale-UKEY patch to a clean source RPM and builds RPMs. |
| `scripts/install_runtime_runner.sh` | Installs the restricted self-hosted runtime entry point and its sudoers rule. |
| `scripts/reproduce_stale_ukey.sh` | Runs the instrumented stale-UKEY reproduction using a root-owned host configuration. |
| `config/ovs-ukey-ci.conf.example` | Example host-specific paths for the self-hosted runtime runner. |
| `.github/workflows/portal-dispatch.yml` | Builds RPMs when the portal sends a repository-dispatch event or when started manually. |
| `.github/workflows/ovs-rpm-check.yml` | Builds the RPM with the spec test suite (%check) enabled. |
| `.github/workflows/runtime-reproduction.yml` | Manually runs the real stale-UKEY reproduction on a specially configured self-hosted runner. |
| `.github/workflows/pytest.yml` | Runs the repository's Python tests. |
| `tests/` | Tests for the portal and validation/evidence handling. |
| `evidence/` | Test reports, logs, checksums, and build/signing evidence. |
| `validation/` | Runtime validation reports and raw runtime evidence. |
| `docs/` | Detailed build, test, and operational documentation. |
| `scripts/ovs-ukey-ci` | Fixed privileged entry point used by the self-hosted workflow. |
| `keys/RPM-GPG-KEY-OVS-STALE-UKEY` | Public key for verifying the project's signed RPMs. It is not a private signing key. |

## 6. Set up and run the web portal

This section runs the portal on your own development machine. It does not require a self-hosted GitHub Actions runner.

### Prerequisites

- Git
- Python 3.9 or newer (use a version compatible with the dependencies in `requirements.txt`)
- Network access to GitHub
- A GitHub fine-grained personal access token for this repository

The portal uses the GitHub API to send a `repository_dispatch` event. For a fine-grained token, grant access only to this repository and set **Contents: Read and write**. GitHub documents this permission for the [Create a repository dispatch event API](https://docs.github.com/en/rest/repos/repos#create-a-repository-dispatch-event).

Keep the token private. Do not paste it into source files, commit it, or share it in screenshots or logs.

### Step 1 — Clone the repository

```bash
git clone https://github.com/abhiwaycoder/ovs-ukey-automation.git
cd ovs-ukey-automation
```

### Step 2 — Create a Python virtual environment

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

### Step 3 — Configure the GitHub connection

Set the environment variables in the terminal where you will run the portal:

```bash
export GITHUB_TOKEN="YOUR_FINE_GRAINED_TOKEN"
export GITHUB_OWNER="abhiwaycoder"
export GITHUB_REPO="ovs-ukey-automation"
```

Replace `YOUR_FINE_GRAINED_TOKEN` with your own token. Do not include the token in a Git commit. These variables need to be present whenever the portal process is started.

### Step 4 — Start the portal

```bash
.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
```

Open this address in your browser:

`http://127.0.0.1:8000/`

You should see the **OVS UKEY Automation Portal** page.

### Step 5 — Submit a build request

The form is prefilled with the source RPM and patch that were validated for this project.

For the current workflow, use these approved inputs:

- Clean source RPM: `openvswitch2.17-2.17.0-106.el8s.src.rpm`
- Tested patch: `openvswitch-2.17.0-stale-ukey.patch`

The workflow currently checks the exact source RPM and patch inputs and their expected checksums. It is **not** a general-purpose builder for arbitrary OVS versions, arbitrary source RPMs, or arbitrary patches.

Submit the form. The portal sends a request to GitHub and returns a unique request ID. A successful submission means GitHub accepted the dispatch request; it does not mean the RPM build has finished.

### Step 6 — Check the build status

Use the request ID returned by the portal:

`http://127.0.0.1:8000/build/REQUEST_ID`

Replace `REQUEST_ID` with the actual UUID returned by your request. The endpoint reports the matching GitHub Actions run, its status, its conclusion, and a link to the run when it is visible.

You can also open the repository's [Actions page](https://github.com/abhiwaycoder/ovs-ukey-automation/actions) and select **OVS Portal RPM Build**.

### Step 7 — Download the build artifact

When the workflow finishes successfully, open the matching Actions run and download its artifact. The normal portal build produces:

- 9 binary RPMs
- 1 source RPM
- Build log
- `SHA256SUMS` checksum manifest

The normal portal-dispatch build uses `--nocheck`; it intentionally does not run the RPM spec's full `%check` test suite. Use the separate test workflow described below for that validation.

## 7. Run the available tests and builds

### A. Run the Python portal tests locally

With the virtual environment active:

```bash
python -m pytest -v
```

These tests cover the portal endpoints, request validation, GitHub dispatch handling, and workflow-status lookup. They do not run Open vSwitch datapath tests.

### B. Run the RPM build with %check

In GitHub:

1. Open the repository's [Actions page](https://github.com/abhiwaycoder/ovs-ukey-automation/actions).
2. Select **OVS RPM Build with Tests**.
3. Select **Run workflow**.
4. Start the workflow on the intended branch and wait for it to finish.
5. Review the job summary and download the test artifact.

This workflow uses a Rocky Linux 8.10 container and runs `scripts/build_rpm.sh` with `--with-check`. The November 3, 2026 run passed with 2,436 tests passed and 1 skipped.

### C. Build RPMs locally (advanced)

The repeatable script expects an EL8-compatible build environment with the RPM build dependencies already installed. It does not download the source RPM or patch for you.

```bash
bash scripts/build_rpm.sh \
  --srpm /path/to/openvswitch2.17-2.17.0-106.el8s.src.rpm \
  --patch /path/to/openvswitch-2.17.0-stale-ukey.patch \
  --topdir /path/to/new-empty-build-directory \
  --jobs 1
```

The default skips `%check`. Add `--with-check` to run the spec test suite:

```bash
bash scripts/build_rpm.sh \
  --srpm /path/to/openvswitch2.17-2.17.0-106.el8s.src.rpm \
  --patch /path/to/openvswitch-2.17.0-stale-ukey.patch \
  --topdir /path/to/new-empty-build-directory \
  --jobs 1 \
  --with-check
```

The output directory contains the RPMs, build log, and checksum manifest. The directory must be new or empty; the script refuses to overwrite existing build data.

For all build options and prerequisites, see [Repeatable RPM build](docs/REPEATABLE_RPM_BUILD.md).

## 8. Runtime reproduction: advanced setup

The real runtime test is different from the hosted RPM build. It starts or connects to a disposable OVS runtime, creates test traffic, removes datapath flows, and checks whether the stale UKEYs are eventually cleaned up.

The manual GitHub Actions workflow is:

`.github/workflows/runtime-reproduction.yml`

It requires a dedicated self-hosted runner with both labels:

- `self-hosted`
- `ovs-ukey`

The runner must have Python and pip, the required test dependencies, the disposable OVS runtime, and the `gha-runner` account. The workflow invokes this narrowly allowed privileged command:

`sudo -n /usr/local/sbin/ovs-ukey-ci`

The configured sudoers rule is intended to allow that exact entry point, rather than unrestricted passwordless root access.

**This runner setup is currently environment-specific.** The reproduction entry point delegates to scripts and OVS files under paths configured for the original Compute1 test environment. The existing reproduction script also contains fixed paths. Do not assume that adding a runner label to an ordinary machine is enough to make the test work. Before using another host, an OVS maintainer must provision an isolated runtime, review and adapt the paths, validate the sudo rule, and ensure the machine has enough memory.

The previous Compute1 runner experienced a host-wide out-of-memory event. Do not restart or reuse it until host memory pressure and OpenStack workload capacity have been assessed.

To start the workflow after the runner has been safely configured:

1. Open the repository's **Actions** page.
2. Select **OVS UKEY Runtime Reproduction**.
3. Select **Run workflow**.
4. Review the run and verify that the workflow observed `missed_dumps=1`, `2`, `3`, and `4`.
5. Confirm the coverage output contains `revalidate_missing_dp_flow`.
6. Download and review the runtime evidence.

Only run this on a disposable test system. Never point it at production OVS sockets or databases.

## 9. Safety and security notes

- Use disposable VMs, containers, and isolated network namespaces for destructive tests.
- Never run the reproduction against production OVS services, sockets, databases, or bridges.
- Do not commit GitHub tokens, private signing keys, GPG home directories, or signing passphrases.
- Verify checksums and RPM signatures before using packages.
- A checksum proves that a file matches a known digest; it does not prove who created the file. A trusted signature and independently verified public-key fingerprint are needed for publisher authenticity.
- A successful RPM build is not the same as a successful %check run, package installation, native-kernel runtime test, or OpenStack validation.
- The public key is available at `keys/RPM-GPG-KEY-OVS-STALE-UKEY`. Verify its fingerprint through an independently authenticated channel before trusting packages.

## 10. More detailed documentation and evidence

- [Build and test results](docs/BUILD_AND_TEST_RESULTS.md) — test history, package build results, and validation scope.
- [Repeatable RPM build instructions](docs/REPEATABLE_RPM_BUILD.md) — build inputs, script options, workflow behavior, and signing notes.
- [Self-hosted runtime runner setup](docs/SELF_HOSTED_RUNTIME_RUNNER.md) — host prerequisites, restricted installation, configuration, and evidence collection.
- [RPM %check validation report](evidence/rpm-check-validation-41572770829.md) — November 3 hosted test results.
- [RPM signing and local DNF repository report](evidence/rpm-signing-validation-20261103.md) — signing and local repository checks.
- [Historical baseline-versus-patched regression report](docs/OVS-STALE-UKEY-VALIDATION.md) — focused regression comparison.
- [Native RHEL 8.10 runtime report](validation/ovs-2.17.8-rhel8-native-runtime-validation/README.md) — November 4 native test and its limitations.
- [Actions workflows](https://github.com/abhiwaycoder/ovs-ukey-automation/actions) — build and test execution history.
- [GitHub Releases](https://github.com/abhiwaycoder/ovs-ukey-automation/releases) — published project inputs and earlier RPM artifacts.

---

