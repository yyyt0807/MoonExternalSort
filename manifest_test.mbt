///|
test "job manifest round-trips every recovery-critical field" {
  let original : JobManifest = {
    phase: Merging,
    input_path: "input 数据.jsonl",
    output_path: "out.txt",
    work_directory: ".work",
    config: SortConfig::new(
      order=Descending,
      key_kind=IntegerKey,
      memory_budget_bytes=4096,
      max_open_runs=3,
      max_record_bytes=1024,
    ),
    selector: JsonField("priority"),
    input_records: 123L,
    initial_run_count: 7,
    merge_pass: 2,
    runs: [
      { path: "p2-g0.run", record_count: 100L, },
      { path: "p2-g1.run", record_count: 23L, },
    ],
  }
  assert_eq(decode_manifest(encode_manifest(original)), original)
}

///|
test "manifest rejects invalid merge fan-in" {
  let invalid =
    #|{"schemaVersion":1,"phase":"runs-ready","inputPath":"i","outputPath":"o","workDirectory":"w","order":"ascending","keyKind":"text","memoryBudgetBytes":256,"maxOpenRuns":1,"maxRecordBytes":64,"selector":{"kind":"whole"},"inputRecords":0,"initialRunCount":0,"mergePass":0,"runs":[]}
  try ignore(decode_manifest(invalid)) catch {
    InvalidManifest(_) => ()
    _ => fail("unexpected SortError variant")
  } noraise {
    _ => fail("expected InvalidManifest")
  }
}

///|
test "manifest preserves decimal key jobs and CSV selectors" {
  let original : JobManifest = {
    phase: RunsReady,
    input_path: "prices.csv",
    output_path: "prices.sorted.csv",
    work_directory: ".prices-work",
    config: SortConfig::new(
      key_kind=DecimalKey,
      memory_budget_bytes=2048,
      max_open_runs=4,
      max_record_bytes=256,
    ),
    selector: CsvField(index=2, delimiter=';'),
    input_records: 40L,
    initial_run_count: 3,
    merge_pass: 0,
    runs: [
      { path: "r0.run", record_count: 15L, },
      { path: "r1.run", record_count: 15L, },
      { path: "r2.run", record_count: 10L, },
    ],
  }
  assert_eq(decode_manifest(encode_manifest(original)), original)
}
