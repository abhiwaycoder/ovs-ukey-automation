# Native RHEL 8.10 signed RPM runtime cleanup validation

**Result: PASS for same-NEVRA signed package replacement, service activation, and observed runtime UKEY cleanup.**

Test environment: disposable RHEL 8.10 VM, `ovs-ukey-rhel8`.

Runtime evidence timestamp: `2026-11-03T22:29:41-05:00`
(2026-11-04 03:29:41 UTC).

## 1. Package details

| Property | Value |
|---|---|
| Operating system | Red Hat Enterprise Linux 8.10 |
| Kernel | `4.18.0-553.158.1.el8_10.x86_64` |
| Package | `openvswitch2.17-2.17.0-106.el8.x86_64` |
| OVS reported version | `2.17.8` |
| Signing key fingerprint | `7F34141A60E9B91DABF3978DFEC22E62BB0AD5CB` |

The signed RPM was produced from the November 3 checked-build artifact:
[GitHub Actions run 41572770829](https://github.com/abhiwaycoder/ovs-ukey-automation/actions/runs/41572770829).

The public key was imported into the VM RPM database. The RPM signature,
header digests, and payload digests passed `rpmkeys --checksig --verbose`.

## 2. Package replacement and service validation

The signed package had the same NEVRA as the previously installed package.
A dry-run replacement transaction passed.

The package was installed using:

    rpm -Uvh --replacepkgs --replacefiles --noscripts \
      /var/tmp/ovs-ukey-preflight/openvswitch2.17-2.17.0-106.el8.x86_64.rpm

The `--noscripts` option was intentional. It avoided running package
scriptlets that could change ownership under `/etc/openvswitch` during
this controlled payload replacement.

Post-install checks:

- `rpm -V openvswitch2.17` reported no differences.
- The installed RPM database showed the expected RSA/SHA512 signature.
- The existing `conf.db` ownership remained `openvswitch:hugetlbfs`,
  mode `640`.
- OVS was explicitly restarted to activate the installed binaries.
- The running `ovs-vswitchd` and `ovsdb-server` executable checksums
  matched the installed executable files.
- `openvswitch`, `ovsdb-server`, and `ovs-vswitchd` were active.
- The test bridge `br-ukey-runtime` remained configured.

This was a same-NEVRA payload replacement, not a different-NEVRA
upgrade or rollback test.

## 3. Runtime test topology

The disposable VM had one OVS bridge, `br-ukey-runtime`, connected to
the test interfaces `ukey-veth-a` and `ukey-veth-b`.

The peers were in separate network namespaces:

| Namespace | Peer interface | Address |
|---|---|---|
| `ukey-ns-a` | `ukey-peer-a` | `198.18.77.1/24` |
| `ukey-ns-b` | `ukey-peer-b` | `198.18.77.2/24` |

The test confirmed that the captured datapath flows belonged to the
test veth interfaces.

## 4. Runtime test procedure and result

1. Generated traffic from `ukey-ns-a` to `198.18.77.2`.
2. Ping completed successfully: 5 packets transmitted, 5 received,
   0% packet loss.
3. Captured 2 datapath flows and 2 UKEYs before deletion.
4. Deleted datapath flows using `ovs-appctl -t ovs-vswitchd dpctl/del-flows`.
5. Confirmed that the datapath flow dump was empty.
6. Sampled the UKEY count approximately every 0.5 seconds.

Observed UKEY counts:

| Sample | UKEY count |
|---:|---:|
| 1 | 2 |
| 2 | 2 |
| 3 | 2 |
| 4 | 2 |
| 5 | 0 |

The final `upcall/show` output reported zero datapath flows and zero UKEYs.
The final `coverage/show` output reported
`revalidate_missing_dp_flow` with `total: 2`.

The three OVS services remained active, and the test bridge remained
configured after the test.

## 5. Raw evidence and integrity

The evidence files in this directory were captured on the RHEL 8.10 VM:

- `bridge-before.txt`
- `coverage-before.txt`
- `coverage-final.txt`
- `delete-time.txt`
- `flows-before-delete.txt`
- `flows-after-delete.txt`
- `ukey-monitor.txt`
- `ukeys-before-delete.txt`
- `ukeys-final.txt`

Verify their integrity from this directory:

    sha256sum -c SHA256SUMS

All nine original evidence-file checksums passed after copying them
from the VM to the Fedora workstation.

## 6. Scope and limitations

This test demonstrates runtime UKEY cleanup using the signed package
on a native RHEL 8.10 kernel after same-NEVRA package replacement.

It does not independently establish:

- The exact `missed_dumps=1,2,3,4` sequence. The installed build did
  not expose the separate `STALE_UKEY_DEBUG` instrumentation needed
  to capture those intermediate values.
- A different-NEVRA package upgrade or rollback.
- First-install behavior or package scriptlet execution. Scriptlets
  were deliberately skipped during this replacement test.
- OpenStack end-to-end network validation.

The final coverage output reports a total of 2 for
`revalidate_missing_dp_flow`. The before-test output did not provide
a matching counter line, so this report does not claim a measured
pre-test to post-test counter delta.
