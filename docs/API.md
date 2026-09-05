# API

## Portable root package

- `SortConfig::new`: validates memory, record-size and merge fan-in budgets.
- `parse_key`: converts external text to a typed text or signed-integer key.
- `compare_records`: orders by key, then ascending input position for stability.
- `RunBuilder::push`: accepts one record and may return a completed sorted Run.
- `RunBuilder::finish`: completes the final non-empty Run.
- `merge_sorted_runs`: heap-based reference merge for materialized Runs.
- `plan_merge_pass`: partitions Run indexes into bounded Merge Groups.
- `LineFramer`: frames arbitrary byte chunks without exceeding record size.
- `encode_run_record` / `decode_run_record`: internal JSONL Run representation.
- `encode_manifest` / `decode_manifest`: versioned recovery document.
- `CsvDialect`, `parse_csv_record`, `select_csv_field`: quoted single-record CSV.
- `SortednessVerifier`: constant-space order and stability diagnostics.
- `TopKSelector`: stable bounded-memory heap selection.
- `estimate_job` / `build_merge_schedule`: deterministic preflight planning.

## Native adapter

- `sort_file(FileSortOptions)`: starts a new file job; refuses an existing work directory.
- `check_file(FileCheckOptions)`: validates ordering without rewriting input.
- `resume_file(manifest_path)`: continues from a committed manifest.
- `report_json`: renders the stable completion report.

Selectors are `WholeRecord`, `DelimitedField`, `CsvField`, and `JsonField`.
`CsvField` supports quoting and doubled quotes within one physical line;
multiline CSV is outside v0.1. JSONL fields must be top-level scalar strings,
numbers, or booleans. `IntegerKey` parses selected text as signed 64-bit integer.

Outputs contain the original record payload, one record per LF-terminated line. CR in CRLF input is removed. A final unterminated input line is accepted; a trailing LF does not invent an extra record.
