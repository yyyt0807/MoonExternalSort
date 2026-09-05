# MoonExternalSort

MoonExternalSort is a stable, bounded-memory external sorting and multi-pass merge engine written in MoonBit. It turns UTF-8 text, delimited records, or JSONL that may exceed memory into immutable sorted Runs, merges them under an explicit file fan-in, and atomically publishes the final output.

## Guarantees

- Equal keys preserve input order in both ascending and descending jobs.
- Retained records are admitted under an explicit byte estimate.
- The byte-oriented line framer rejects oversized records before unbounded line buffering.
- A Merge Group opens at most `max_open_runs` input Runs.
- Only fully written Runs enter an atomically replaced Job Manifest.
- Final output becomes visible through one rename after complete materialization.
- Recovery trusts the last committed manifest, not partial files from an interrupted pass.

`memory_budget_bytes` covers records retained while building Runs. During a
merge, decoded record heads are bounded separately by `max_open_runs`; for text
keys their conservative retained-data ceiling is
`max_open_runs * (2 * max_record_bytes + 32)`. Neither bound is an
operating-system RSS limit, and both exclude runtime, filesystem, heap-container
and encoder overhead.

## Verify

```sh
moon update
moon check --target all --deny-warn
moon test --target all --deny-warn
moon run examples/library-demo
```

Sort the first TSV field as a signed integer:

```sh
moon run --target native cmd/moon-external-sort -- sort \
  examples/data/records.tsv _build/sorted.tsv \
  --field-index 0 --numeric \
  --memory-bytes 512 --max-record-bytes 128
```

Sort a top-level JSONL field in descending order:

```sh
moon run --target native cmd/moon-external-sort -- sort \
  examples/data/events.jsonl _build/events.sorted.jsonl \
  --json-field priority --numeric --descending --force
```

Resume from the last committed state:

```sh
moon run --target native cmd/moon-external-sort -- resume \
  OUTPUT.moon-sort-work/manifest.json
```

See [API](docs/API.md), [architecture](docs/ARCHITECTURE.md), [testing](docs/TESTING.md), [security](docs/SECURITY.md), and the [ecosystem comparison](docs/ECOSYSTEM_COMPARISON.md). The project is an original MoonBit implementation licensed under Apache-2.0.
