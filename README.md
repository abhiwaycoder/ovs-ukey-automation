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
