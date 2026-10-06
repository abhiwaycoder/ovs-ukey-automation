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
