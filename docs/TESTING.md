# Testing

Run the strict local suite:

```sh
moon check --target all --deny-warn
moon test --target all --deny-warn
moon fmt --check
moon info
```

Portable tests cover invalid budgets, numeric ordering, descending stability, bounded Run spills, oversized records, empty Runs, heap merge equivalence, fan-in planning, Run codec round trips, manifest validation, chunk-boundary line framing and record limits.

They also cover quoted CSV syntax and round trips, streaming order diagnostics,
stable Top-K selection, aggregate selection budgets, merge schedules, saturating
I/O estimates and planner JSON output.

Exact-decimal tests cover canonicalization, negative values, scale alignment,
precision beyond IEEE-754, Run/Manifest round trips and Native file sorting.
Group-statistics tests cover empty, singleton, duplicate, descending and
disordered streams.

Native tests create isolated paths under `_build`, exercise multi-Run sorting, JSONL numeric sorting, atomic publication, manifest persistence, and recovery from two committed Runs. Tests remove only the exact test directories they create.

Native coverage additionally exercises quoted CSV sorting, filesystem order
checking and CLI parsing.

Before acceptance, add benchmark fixtures for at least one million records and record wall time, peak process memory, total temporary bytes, initial Run count and merge-pass count. Benchmarks must first compare output with an in-memory reference.
