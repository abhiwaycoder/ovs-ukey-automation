# Repeatable RPM build script validation

**Result: PASS**

The repository script `scripts/build_rpm.sh` was executed in the Rocky Linux 8.10 build container using the clean original EL8S source RPM and the verified stale-UKEY patch.

## Invocation

```bash
bash scripts/build_rpm.sh \
  --srpm openvswitch2.17-2.17.0-106.el8s.src.rpm \
  --patch openvswitch-2.17.0-stale-ukey.patch \
  --topdir /work/ci-script-validation.hIz7sn/output \
  --jobs 1
```

The script used its default `--nocheck` behavior. The RPM spec `%check` stage was not executed.

## Results

- Build completed successfully and reached the spec `%clean` stage.
- 9 binary RPMs and 1 source RPM were generated.
- All 10 RPM files passed `rpm -K` digest verification (`digests OK`).
- A `build.log` and `SHA256SUMS` manifest were generated.
- RPMs are not signed by this build.

## Generated artifacts

| Package | Size (bytes) | SHA-256 |
|---|---:|---|
| `openvswitch2.17-test-2.17.0-106.el8.noarch.rpm` | 137,388 | `70f89ead05ccd07b0bf286a6be3877042710528295c68da3fc7382491902bca5` |
| `network-scripts-openvswitch2.17-2.17.0-106.el8.x86_64.rpm` | 90,996 | `db1e6ed9a7111f164d878a2904c13632a939ab305b6e43d591c9d9d24da60056` |
| `openvswitch2.17-2.17.0-106.el8.x86_64.rpm` | 6,829,664 | `a4dc0629ad010880e0324bffea834006c6e369492c4cc8a7a6457cb43e114f25` |
| `openvswitch2.17-debuginfo-2.17.0-106.el8.x86_64.rpm` | 29,141,508 | `81bb519cf231196baf4f6619db76407136aa4d0f0f48ec5dae632cd6306a01d4` |
| `openvswitch2.17-debugsource-2.17.0-106.el8.x86_64.rpm` | 7,022,232 | `e4c46ce66ffb80f1b768e6a1bf3ff7bbb5be16b3b4122b3b6a8b3610ef50565e` |
| `openvswitch2.17-devel-2.17.0-106.el8.x86_64.rpm` | 221,048 | `977ce7a16cce38eb58d4e10e9d7e1caf5e7ffc3e309b8d3c2dbf45e302fdf303` |
| `openvswitch2.17-ipsec-2.17.0-106.el8.x86_64.rpm` | 99,376 | `18c9cf034c6457f6fb2dcf458ba7f07a6ccb7489cd922e52cc170dd1c7fa5388` |
| `python3-openvswitch2.17-2.17.0-106.el8.x86_64.rpm` | 314,348 | `d088c51a61cbda3804a0fcb057700a6d3b6c8e22598a024beeedc60ed04ba179` |
| `python3-openvswitch2.17-debuginfo-2.17.0-106.el8.x86_64.rpm` | 104,636 | `2a7ce95f88e88d9b305f9bf307890884f0483c85b0d851d0b06b9a33116114ac` |
| `openvswitch2.17-2.17.0-106.el8.src.rpm` | 31,710,933 | `e14797ce790b1f6c16a0fe0da74da405983d7cbb79ba038ebbbef774a356378f` |

## Limitations

This validates the script's clean-SRPM preparation, patch application, package build, RPM digest checks, and checksum manifest generation. It does not validate the RPM `%check` suite, sign the packages, install the generated packages, or run the stale-UKEY runtime reproduction.
