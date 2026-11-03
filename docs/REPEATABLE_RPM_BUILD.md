# Repeatable Open vSwitch RPM build

This procedure builds the OVS 2.17.0 RPM set from a clean original source RPM
and the tested stale-UKEY patch.

## Build inputs

The hosted workflow uses the clean CentOS Stream 8 NFV source RPM:

`https://vault.centos.org/8-stream/nfv/Source/openvswitch-2/openvswitch2.17-2.17.0-106.el8s.src.rpm`

The CentOS Vault directory listing reports this file as 31,709,062 bytes. The
workflow checks the downloaded size and RPM name/version/release. This is a
historical source archive snapshot, not a current package update channel.

The stale-UKEY patch is distributed as a GitHub Release asset named
`openvswitch-2.17.0-stale-ukey.patch` at tag
`ovs-2.17.0-106.el8-build-inputs`.

Expected patch SHA-256:

`454abe3e7f6f48ba7543a6c5b636129f9d6e56422a15e7fc06f0215d4ffce4cc`

The workflow rejects a patch whose SHA-256 differs. Do not substitute the
alternate patch or use an SRPM produced by a previous patched build.

## Local example

Run inside an EL8-compatible build container where the RPM build dependencies
are already installed:

```bash
bash scripts/build_rpm.sh \
  --srpm /work/inputs/openvswitch2.17-2.17.0-106.el8s.src.rpm \
  --patch /work/inputs/openvswitch-2.17.0-stale-ukey.patch \
  --topdir /work/builds/ovs-2.17.0-stale-ukey \
  --jobs 1
```

The default is one build job and `--nocheck`. To run the spec's `%check`
section explicitly, add `--with-check`. An optional `--dist el8` argument
sets the RPM dist macro to `.el8`; otherwise the build environment's dist
macro is used.

## GitHub Actions build

`.github/workflows/portal-dispatch.yml` handles both the FastAPI
`repository_dispatch` request and a manual `workflow_dispatch`. It runs on
GitHub-hosted infrastructure with a Rocky Linux 8.10 container, installs the
SRPM's BuildRequires, downloads and validates the clean source RPM, verifies
the tested patch SHA-256, and invokes `scripts/build_rpm.sh` with one job and
`--nocheck`.

The workflow uploads nine binary RPMs, one source RPM, the build log, and
`SHA256SUMS` as a GitHub Actions artifact. The artifacts are available from
the workflow run for 14 days.

### Separate RPM `%check` workflow

The repository also has
`.github/workflows/ovs-rpm-check.yml`, which performs a checked RPM build
using the same clean source RPM and verified stale-UKEY patch. Unlike the
portal-dispatch build above, this workflow invokes
`scripts/build_rpm.sh` with `--with-check`, one build job, and runs on a
GitHub-hosted Rocky Linux 8.10 container with Docker `--init`.

The November 3, 2026 run completed successfully:
- [Workflow run 41572770829](https://github.com/abhiwaycoder/ovs-ukey-automation/actions/runs/41572770829).
- Full `%check` suite: **2,436 passed, 1 skipped**.
- Targeted test 1305, `Cleanup missing datapath flows`: **PASS**.
- 9 binary RPMs and 1 source RPM generated.
- RPM digest verification and evidence artifact upload completed.

Artifact name: `ovs-rpm-check-validation-41572770829`
(artifact ID `13204797978`). The workflow artifact is retained for 30 days.
The workflow does not enable kernel datapath tests.


The portal-dispatch workflow does not sign packages, publish a package
repository, install OVS, or run the datapath reproduction. The separate
`ovs-rpm-check.yml` workflow runs the RPM spec `%check` suite, but it does
not enable kernel datapath tests. Runtime reproduction remains separate and
requires a healthy, resource-appropriate self-hosted runner. The Compute1
runner previously encountered host-wide OOM pressure and must not be
restarted until host memory pressure and OpenStack workload capacity have
been addressed.

## What the script does

1. Extracts the source RPM into a temporary directory.
2. Checks that its spec has one unnumbered vendor patch and one matching
   `%patch -p1` invocation, and rejects an already-patched spec.
3. Copies the source files into a new rpmbuild top directory.
4. Adds the stale-UKEY patch as `Patch1`, after the vendor patch in
   `%prep`.
5. Runs `rpmbuild -ba` with the requested parallelism.
6. Verifies each generated RPM using `rpm -K`.
7. Writes `build.log` and `SHA256SUMS` under the output top directory.

The input SRPM and patch are not modified. The output directory must be empty
or not exist; the script will not overwrite existing build artifacts.

## Expected outputs

```text
<topdir>/
├── BUILD/
├── BUILDROOT/
├── RPMS/
├── SOURCES/
├── SPECS/
├── SRPMS/
├── build.log
└── SHA256SUMS
```

`rpm -K` reports package digest/signature verification status. It does not
sign the packages. Signing and repository publication are separate release
steps.

## Safety and validation

- Run only with trusted source RPMs and patches, inside an isolated build
  container. RPM spec files execute build commands.
- Do not expose GitHub tokens or other credentials to the build container.
- This script builds and packages RPMs; it does not install them, start
  Open vSwitch services, or run the stale-UKEY reproduction.
- A build using the default `--nocheck` setting does not validate the spec's
  `%check` suite. Record that qualification in build reports and release notes.
- Use a suitable host with adequate memory for `--with-check`; the prior full
  test run on the 3 GiB Compute1 host experienced global OOM pressure.

## Script execution evidence

The repository build script was executed successfully in the Rocky Linux 8.10
container with the clean original source RPM and stale-UKEY patch. It generated
nine binary RPMs and one source RPM; all ten passed `rpm -K` digest
verification. The default `--nocheck` mode was used, so the spec's `%check`
stage was skipped.

See [evidence/repeatable-rpm-build-validation.md](../evidence/repeatable-rpm-build-validation.md)
for the exact invocation, artifact sizes, and SHA-256 values.
