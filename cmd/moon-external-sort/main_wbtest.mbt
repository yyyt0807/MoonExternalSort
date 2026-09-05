///|
fn expect_parse_error(args : Array[String], expected : String) -> Unit raise {
  match parse_command(args) {
    Err(actual) => assert_eq(actual, expected)
    Ok(_) => abort("expected command parse error")
  }
}

///|
test "estimate command parses 64-bit counts and budgets" {
  let command = parse_command([
    "moon-external-sort", "estimate", "10000000000", "800000000000", "--memory-bytes",
    "4096", "--max-open-runs", "8", "--max-record-bytes", "256", "--numeric",
  ])
  guard command is Ok(Estimate(records, bytes, config)) else {
    abort("expected estimate command")
  }
  assert_eq(records, 10000000000L)
  assert_eq(bytes, 800000000000L)
  assert_eq(config.memory_budget_bytes, 4096)
  assert_eq(config.max_open_runs, 8)
  assert_eq(config.max_record_bytes, 256)
  assert_eq(config.key_kind, @sort.IntegerKey)
}

///|
test "estimate command rejects malformed and negative counts" {
  expect_parse_error(
    ["moon-external-sort", "estimate", "not-int", "10"],
    "expected a 64-bit integer, got: not-int",
  )
  expect_parse_error(
    ["moon-external-sort", "estimate", "-1", "10"],
    "estimate counts must not be negative",
  )
  expect_parse_error(
    ["moon-external-sort", "estimate", "10", "-1"],
    "estimate counts must not be negative",
  )
}

///|
test "estimate command rejects missing and unknown options" {
  expect_parse_error(
    ["moon-external-sort", "estimate", "10"],
    "estimate requires INPUT_RECORDS and INPUT_BYTES",
  )
  expect_parse_error(
    ["moon-external-sort", "estimate", "10", "100", "--unknown"],
    "unknown estimate option: --unknown",
  )
  expect_parse_error(
    ["moon-external-sort", "estimate", "10", "100", "--memory-bytes"],
    "--memory-bytes requires a value",
  )
}

///|
test "check command parses quoted CSV selector" {
  let command = parse_command([
    "moon-external-sort", "check", "input.csv", "--csv-field", "2", "--csv-delimiter",
    ";", "--numeric", "--descending", "--max-record-bytes", "2048",
  ])
  guard command is Ok(Check(options)) else { abort("expected check command") }
  assert_eq(options.input_path, "input.csv")
  assert_eq(options.selector, @sort.CsvField(index=2, delimiter=';'))
  assert_eq(options.config.key_kind, @sort.IntegerKey)
  assert_eq(options.config.order, @sort.Descending)
  assert_eq(options.config.max_record_bytes, 2048)
}

///|
test "sort command enforces one selector" {
  expect_parse_error(
    [
      "moon-external-sort", "sort", "input", "output", "--field-index", "0", "--json-field",
      "priority",
    ],
    "only one key selector may be specified",
  )
}

///|
test "CSV delimiter must follow CSV selector and be one character" {
  expect_parse_error(
    ["moon-external-sort", "check", "input", "--csv-delimiter", ";"],
    "--csv-delimiter requires --csv-field first",
  )
  expect_parse_error(
    [
      "moon-external-sort", "check", "input", "--csv-field", "0", "--csv-delimiter",
      "||",
    ],
    "--csv-delimiter requires exactly one character",
  )
}

///|
test "resume accepts only optional force" {
  guard parse_command(["moon-external-sort", "resume", "manifest.json"])
    is Ok(Resume(path, replace)) else {
    abort("expected resume command")
  }
  assert_eq(path, "manifest.json")
  assert_false(replace)
  guard parse_command([
      "moon-external-sort", "resume", "manifest.json", "--force",
    ])
    is Ok(Resume(forced_path, forced_replace)) else {
    abort("expected forced resume command")
  }
  assert_eq(forced_path, "manifest.json")
  assert_true(forced_replace)
  expect_parse_error(
    ["moon-external-sort", "resume", "manifest.json", "--other"],
    "unknown resume option: --other",
  )
}

///|
test "sort command preserves explicit workspace and delimiter" {
  let command = parse_command([
    "moon-external-sort", "sort", "input.psv", "output.psv", "--field-index", "3",
    "--delimiter", "|", "--work-dir", "scratch/job-1", "--memory-bytes", "2048",
    "--max-open-runs", "4", "--max-record-bytes", "512", "--force",
  ])
  guard command is Ok(Sort(options)) else { abort("expected sort command") }
  assert_eq(options.input_path, "input.psv")
  assert_eq(options.output_path, "output.psv")
  assert_eq(options.work_directory, "scratch/job-1")
  assert_eq(options.selector, @sort.DelimitedField(index=3, delimiter="|"))
  assert_eq(options.config.memory_budget_bytes, 2048)
  assert_eq(options.config.max_open_runs, 4)
  assert_true(options.replace_output)
}

///|
test "check command rejects invalid record budget" {
  expect_parse_error(
    ["moon-external-sort", "check", "input", "--max-record-bytes", "0"],
    "invalid check record budget",
  )
}

///|
test "estimate command uses production defaults" {
  guard parse_command(["moon-external-sort", "estimate", "100", "1000"])
    is Ok(Estimate(records, bytes, config)) else {
    abort("expected default estimate command")
  }
  assert_eq(records, 100L)
  assert_eq(bytes, 1000L)
  assert_eq(config.memory_budget_bytes, 8 * 1024 * 1024)
  assert_eq(config.max_open_runs, 32)
  assert_eq(config.max_record_bytes, 1024 * 1024)
  assert_eq(config.key_kind, @sort.TextKey)
}

///|
test "help version and unknown commands are distinguished" {
  guard parse_command(["moon-external-sort"]) is Ok(Help) else {
    abort("expected implicit help")
  }
  guard parse_command(["moon-external-sort", "--version"]) is Ok(Version) else {
    abort("expected version")
  }
  expect_parse_error(
    ["moon-external-sort", "unknown"],
    "unknown command: unknown",
  )
}
