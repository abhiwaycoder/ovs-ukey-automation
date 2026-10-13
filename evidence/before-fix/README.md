# Historical Pre-Fix Evidence

These files are retained from an earlier stale UKEY investigation run.

## Available artifacts

- `ovs-vswitchd.log`: Earlier OVS daemon log (43 lines).
- `coverage-final.txt`: Earlier coverage output.
- `dp-final.txt`: Empty datapath snapshot (0 bytes).
- `upcall-final.txt`: Earlier upcall statistics.

## Limitations

The historical coverage file does not contain the
`revalidate_missing_dp_flow` marker when checked.

The datapath snapshot is empty, so it cannot be used to establish the
datapath flow state for that run.

These files are preserved for historical reference only. They do not
constitute a complete, validated baseline and should not be compared
quantitatively with later runs without further investigation.
