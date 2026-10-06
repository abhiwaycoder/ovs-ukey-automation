# OVS Stale UKEY Automation

Automated validation for the Open vSwitch stale `ukey` cleanup behavior.

## What this validates

The test validates captured runtime evidence showing that the OVS
revalidator:

1. Detects a UKEY missing from the datapath.
2. Increments `missed_dumps` consecutively from 1 through 4.
3. Attempts to delete the missing datapath flow after the fourth miss.
4. Records the `revalidate_missing_dp_flow` coverage counter.
5. Produces the expected cleanup evidence.

The current automation validates previously captured OVS runtime
evidence. It does not yet build or launch OVS and reproduce the
scenario from scratch.

## Tests

Run:

    python3 -m pytest -v

The test suite verifies:

- `missed_dumps=1`
- `missed_dumps=2`
- `missed_dumps=3`
- `missed_dumps=4`
- datapath deletion attempt
- `No such file or directory` for the already-missing datapath flow
- `revalidate_missing_dp_flow` coverage
- required evidence files

## Shell validation

Run:

    ./scripts/check_stale_ukey.sh

Expected result:

    STALE UKEY EVIDENCE: PASS

## Evidence location

By default, tests expect captured evidence under:

    /root/ovs-ukey-evidence-check/ovs-ukey-evidence

The location can be overridden with:

    OVS_UKEY_EVIDENCE=/path/to/evidence python3 -m pytest -v

## Upstream OVS fix

The stale-UKEY cleanup behavior being validated originates from:

    ce789d991f748d95a34355e7813ddf18a64de504
    ofproto-dpif-upcall: Avoid stale ukeys leaks.

The fix tracks consecutive datapath-dump misses and removes the UKEY
after four consecutive misses.

A follow-up upstream commit initializes the counter:

    bc82c01d0b23f55ed25363f749ba59c5822c0495
    ofproto-dpif-upcall: Fix use of uninitialized missed dumps counter.

## Future work

The next stage is to replace captured-evidence validation with a
self-contained disposable OVS reproduction, followed by CI execution
through GitHub Actions.
