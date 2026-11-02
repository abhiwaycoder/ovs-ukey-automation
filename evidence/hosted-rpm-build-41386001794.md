# Hosted RPM build validation — run 41386001794

**Result: PASS**

On November 2, 2026, the GitHub Actions workflow built the Open vSwitch
2.17.0-106.el8 RPM set from the clean CentOS Stream 8 NFV source RPM and the
published stale-UKEY patch. The build ran in a Rocky Linux 8.10 container on
GitHub-hosted infrastructure.

## Workflow

- Run: [41386001794](https://github.com/abhiwaycoder/ovs-ukey-automation/actions/runs/41386001794)
- Event: push to the temporary validation branch
- Commit: `588aef17e735b4a7397eeb2e4a6475db51c83735`
- Job: `rpm-build`
- Final conclusion: `success`
- Source RPM: `openvswitch2.17-2.17.0-106.el8s.src.rpm`
- Patch Release asset:
  `openvswitch-2.17.0-stale-ukey.patch`
- Patch SHA-256:
  `454abe3e7f6f48ba7543a6c5b636129f9d6e56422a15e7fc06f0215d4ffce4cc`

The source RPM download, RPM metadata/size checks, BuildRequires installation,
patch download and patch SHA-256 check all passed.

## Build result

- RPM build completed successfully and reached the spec `%clean` stage.
- 9 binary RPMs and 1 source RPM were generated.
- The build script ran `rpm -K` on all 10 generated RPMs; all reported
  `digests OK` in the GitHub Actions job log.
- `SHA256SUMS` was generated and all ten entries were independently checked
  against the downloaded artifact archive.
- The archive contains the RPM files, `build.log`, and `SHA256SUMS`.

## Generated binary RPMs

1. `openvswitch2.17-2.17.0-106.el8.x86_64.rpm`
2. `openvswitch2.17-test-2.17.0-106.el8.noarch.rpm`
3. `openvswitch2.17-devel-2.17.0-106.el8.x86_64.rpm`
4. `openvswitch2.17-ipsec-2.17.0-106.el8.x86_64.rpm`
5. `openvswitch2.17-debuginfo-2.17.0-106.el8.x86_64.rpm`
6. `openvswitch2.17-debugsource-2.17.0-106.el8.x86_64.rpm`
7. `python3-openvswitch2.17-2.17.0-106.el8.x86_64.rpm`
8. `python3-openvswitch2.17-debuginfo-2.17.0-106.el8.x86_64.rpm`
9. `network-scripts-openvswitch2.17-2.17.0-106.el8.x86_64.rpm`

Source RPM:

- `openvswitch2.17-2.17.0-106.el8.src.rpm`

## Generated RPM SHA-256 values

| Package file | SHA-256 |
|---|---|
| `openvswitch2.17-test-2.17.0-106.el8.noarch.rpm` | `02f04998c66e364caf1ab9f8082b6b0125399f5056caf464a2448cb15dc6fb4a` |
| `network-scripts-openvswitch2.17-2.17.0-106.el8.x86_64.rpm` | `477b76994e452769bb6122f7429a4fc4651f0083e0dabfd73d97a2ec1dba6059` |
| `openvswitch2.17-2.17.0-106.el8.x86_64.rpm` | `22cc021ac5035e90fe24c1b1a2ef9e1104e9cda2abb0b931f85d6ecd1aa1a2d5` |
| `openvswitch2.17-debuginfo-2.17.0-106.el8.x86_64.rpm` | `3502b52cd26f8dec909b807b56ca7eddd4557d7e9a807a71d6737959b31fc442` |
| `openvswitch2.17-debugsource-2.17.0-106.el8.x86_64.rpm` | `5dc5acd2d5dda9ee94afae5461d5264f8b1e9c375f9c653c3f8cca0187cffe58` |
| `openvswitch2.17-devel-2.17.0-106.el8.x86_64.rpm` | `83c0efe5d43ecf19e243d5cdb953d00d3eaf2a5ac009aec8e489ae2d57093962` |
| `openvswitch2.17-ipsec-2.17.0-106.el8.x86_64.rpm` | `f2125db4f44c9b7e67916a188482f646074c9c5cd62ef0b184622078f0ef2a69` |
| `python3-openvswitch2.17-2.17.0-106.el8.x86_64.rpm` | `1e6c7a25004529a03b2055207765c724a9461751df425a653edd098c820ad6cd` |
| `python3-openvswitch2.17-debuginfo-2.17.0-106.el8.x86_64.rpm` | `62d5a08b0b176fab5966936ecb3d4a3a3cc8785ef5cfa50da2ea74ec2bf3c57a` |
| `openvswitch2.17-2.17.0-106.el8.src.rpm` | `2db0a5b47d58953cd102db741e6d7cfa872b2c55a2add4eb93b8e0148393cf07` |

## Artifact archive

- Name: `ovs-rpm-build-41386001794`
- Artifact ID: `13116080041`
- ZIP size: 75,040,261 bytes
- ZIP SHA-256:
  `aff18e70c5bdd1f2eba75134b8aa4759e92aa25a3ca97de787935837fdd04a3a`
- Retention: 14 days from upload (expires November 16, 2026)

The archive was downloaded and inspected. All ten `SHA256SUMS` entries
matched the RPM files. The separate GitHub Actions log records successful
`rpm -K` digest checks for all ten packages.

## Limitations

The workflow used the default `--nocheck` mode. The RPM spec `%check`
section was not run. The RPMs are unsigned. This result validates hosted
source preparation, patch validation, package compilation, RPM digest
verification, and artifact upload. It does not establish a passing full OVS
test suite, package installation, service health, or OpenStack/runtime
validation. Those remain separate validation milestones.
