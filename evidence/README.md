# Stale UKEY Reproduction Evidence

This directory stores diagnostic artifacts from the stale UKEY reproduction
workflow on the configured OVS test environment.

## Current artifacts

- `stale-ukey-debug.log`: Instrumentation showing UKEY missed-dump progression.
- `coverage-final.txt`: Coverage counters collected during reproduction.
- `dp-final.txt`: Datapath flow snapshot at collection time.
- `upcall-final.txt`: Upcall statistics and revalidator key counts.
- `ovs-vswitchd.log`: OVS userspace daemon log from the reproduction run.
- `before-fix/`: Earlier captured artifacts retained for comparison.
- `reproduction-summary.txt`: Summary of observations from the captured run.

## Observations

The captured debug log shows stale UKEY entries progressing through missed
dump counts 1, 2, 3, and 4. The log also records datapath flow deletion
attempts that return "No such file or directory".

The coverage output reports a total of 26 for `revalidate_missing_dp_flow`
in this run.

The final snapshots show the state at collection time. They are not, by
themselves, proof that every stale UKEY was removed; new flows or UKEYs may
be created during or after cleanup.

These artifacts document reproduction behavior, not proof that a candidate
patch fixes the issue.

## Regeneration

Run the documented reproduction workflow on its configured test environment.
The live artifacts are collected under:

`/var/lib/ovs-ukey-ci/evidence/`

Copy the resulting artifacts into this directory when updating the checked-in
evidence. Update the summary to match the actual run; do not assume counters
or final flow counts remain constant between runs.
