# Repeatable Open vSwitch RPM build

This procedure builds the OVS 2.17.0 RPM set from a **clean original source RPM**
and the stale-UKEY patch. Run it inside an EL8-compatible build environment
where the RPM build dependencies are already installed.

## Inputs

- An original, unmodified Open vSwitch source RPM.
- The stale-UKEY patch file.
- An empty output directory.

Do not use a source RPM produced by a previous patched build. Its spec already
contains the stale-UKEY patch, and applying the patch again would be incorrect.
The script rejects an input spec that already has `Patch1:` or references the
stale-UKEY patch filename.

## Example

The paths below are examples; make sure they exist inside the build container:

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

## Safety and validation notes

- Run only with trusted source RPMs and patches, inside an isolated build
  container. RPM spec files execute build commands.
- Do not expose GitHub tokens or other credentials to the build container.
- This script builds and packages RPMs; it does not install them, start
  Open vSwitch services, or run the stale-UKEY reproduction.
- A build using the default `--nocheck` setting does not validate the spec's
  `%check` suite. Record that qualification in build reports and release notes.
- Use a suitable host with adequate memory for `--with-check`; the prior full
  test run on the 3 GiB Compute1 host experienced global OOM pressure.
