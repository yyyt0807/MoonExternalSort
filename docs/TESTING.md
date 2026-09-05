# Testing

Run the strict local suite:

```sh
moon check --target all --deny-warn
moon test --target all --deny-warn
moon fmt --check
moon info
```

Portable tests cover invalid budgets, numeric ordering, descending stability, bounded Run spills, oversized records, empty Runs, heap merge equivalence, fan-in planning, Run codec round trips, manifest validation, chunk-boundary line framing and record limits.

Native tests create isolated paths under `_build`, exercise multi-Run sorting, JSONL numeric sorting, atomic publication, manifest persistence, and recovery from two committed Runs. Tests remove only the exact test directories they create.

Before acceptance, add benchmark fixtures for at least one million records and record wall time, peak process memory, total temporary bytes, initial Run count and merge-pass count. Benchmarks must first compare output with an in-memory reference.
