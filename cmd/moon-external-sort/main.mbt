///|
extern "C" fn process_exit(code : Int) = "exit"

///|
priv enum Command {
  Sort(@native.FileSortOptions)
  Check(@native.FileCheckOptions)
  Resume(String, Bool)
  Help
  Version
}

///|
async fn main {
  let args = @env.args()
  let command = match parse_command(args) {
    Ok(value) => value
    Err(message) => {
      @stdio.stderr.write("MOON_EXTERNAL_SORT_ARGUMENT: " + message + "\n")
      @stdio.stderr.write(usage())
      process_exit(2)
      return
    }
  }
  try {
    match command {
      Help => @stdio.stdout.write(usage())
      Version => @stdio.stdout.write("moon-external-sort 0.1.0\n")
      Sort(options) => {
        let report = @native.sort_file(options)
        @stdio.stdout.write(@native.report_json(report) + "\n")
      }
      Check(options) => {
        let report = @native.check_file(options)
        @stdio.stdout.write(@native.check_report_json(report) + "\n")
        if !report.sorted {
          process_exit(8)
        }
      }
      Resume(manifest, replace) => {
        let report = @native.resume_file(manifest, replace_output=replace)
        @stdio.stdout.write(@native.report_json(report) + "\n")
      }
    }
  } catch {
    @native.WorkspaceExists(message) => fail("WORKSPACE_EXISTS", message, 3)
    @native.OutputExists(message) => fail("OUTPUT_EXISTS", message, 3)
    @native.InvalidInput(message) => fail("INVALID_INPUT", message, 4)
    @native.MissingArtifact(message) => fail("MISSING_ARTIFACT", message, 5)
    @native.CorruptRun(message) => fail("CORRUPT_RUN", message, 6)
    @sort.InvalidConfig(message) => fail("INVALID_CONFIG", message, 2)
    @sort.InvalidKey(message) => fail("INVALID_KEY", message, 4)
    @sort.RecordTooLarge(actual~, limit~) =>
      fail(
        "RECORD_TOO_LARGE",
        "record requires " +
        actual.to_string() +
        " bytes; limit is " +
        limit.to_string(),
        4,
      )
    @sort.SequenceExhausted =>
      fail("SEQUENCE_EXHAUSTED", "input position space exhausted", 4)
    @sort.MalformedRun(message) => fail("MALFORMED_RUN", message, 6)
    @sort.InvalidManifest(message) => fail("INVALID_MANIFEST", message, 6)
    @sort.InvalidDialect(message) => fail("INVALID_CSV_DIALECT", message, 4)
    @sort.MalformedCsv(offset~, message~) =>
      fail("MALFORMED_CSV", "byte " + offset.to_string() + ": " + message, 4)
    @sort.CsvFieldMissing(index~, available~) =>
      fail(
        "CSV_FIELD_MISSING",
        "requested " +
        index.to_string() +
        ", available " +
        available.to_string(),
        4,
      )
    error => fail("IO", error.to_string(), 7)
  }
}

///|
fn parse_command(args : Array[String]) -> Result[Command, String] {
  if args.length() == 1 {
    return Ok(Help)
  }
  match args[1] {
    "help" | "--help" | "-h" => Ok(Help)
    "version" | "--version" | "-V" => Ok(Version)
    "resume" => parse_resume(args)
    "sort" => parse_sort(args)
    "check" => parse_check(args)
    value => Err("unknown command: " + value)
  }
}

///|
fn parse_check(args : Array[String]) -> Result[Command, String] {
  if args.length() < 3 {
    return Err("check requires INPUT")
  }
  let input = args[2]
  let mut max_record = 1024 * 1024
  let mut order = @sort.Ascending
  let mut key_kind = @sort.TextKey
  let mut selector = @sort.WholeRecord
  let mut selector_set = false
  let mut index = 3
  while index < args.length() {
    match args[index] {
      "--max-record-bytes" => {
        guard index + 1 < args.length() else {
          return Err("--max-record-bytes requires a value")
        }
        max_record = match parse_int(args[index + 1]) {
          Ok(value) => value
          Err(message) => return Err(message)
        }
        index += 2
      }
      "--descending" => {
        order = @sort.Descending
        index += 1
      }
      "--numeric" => {
        key_kind = @sort.IntegerKey
        index += 1
      }
      "--field-index" => {
        if selector_set {
          return Err("only one key selector may be specified")
        }
        guard index + 1 < args.length() else {
          return Err("--field-index requires a zero-based index")
        }
        let field_index = match parse_int(args[index + 1]) {
          Ok(value) => value
          Err(message) => return Err(message)
        }
        selector = @sort.DelimitedField(index=field_index, delimiter="\t")
        selector_set = true
        index += 2
      }
      "--delimiter" => {
        guard index + 1 < args.length() else {
          return Err("--delimiter requires a value")
        }
        guard selector is @sort.DelimitedField(index=field_index, ..) else {
          return Err("--delimiter requires --field-index first")
        }
        let delimiter = if args[index + 1] == "tab" {
          "\t"
        } else {
          args[index + 1]
        }
        selector = @sort.DelimitedField(index=field_index, delimiter~)
        index += 2
      }
      "--json-field" => {
        if selector_set {
          return Err("only one key selector may be specified")
        }
        guard index + 1 < args.length() else {
          return Err("--json-field requires a top-level field name")
        }
        selector = @sort.JsonField(args[index + 1])
        selector_set = true
        index += 2
      }
      "--csv-field" => {
        if selector_set {
          return Err("only one key selector may be specified")
        }
        guard index + 1 < args.length() else {
          return Err("--csv-field requires a zero-based index")
        }
        let field_index = match parse_int(args[index + 1]) {
          Ok(value) => value
          Err(message) => return Err(message)
        }
        selector = @sort.CsvField(index=field_index, delimiter=',')
        selector_set = true
        index += 2
      }
      "--csv-delimiter" => {
        guard index + 1 < args.length() else {
          return Err("--csv-delimiter requires one character")
        }
        guard selector is @sort.CsvField(index=field_index, ..) else {
          return Err("--csv-delimiter requires --csv-field first")
        }
        let chars = args[index + 1].to_array()
        if chars.length() != 1 {
          return Err("--csv-delimiter requires exactly one character")
        }
        selector = @sort.CsvField(index=field_index, delimiter=chars[0])
        index += 2
      }
      value => return Err("unknown check option: " + value)
    }
  }
  let memory = if max_record < 256 { 256 } else { max_record }
  let config = @sort.SortConfig::new(
    order~,
    key_kind~,
    memory_budget_bytes=memory,
    max_open_runs=2,
    max_record_bytes=max_record,
  ) catch {
    _ => return Err("invalid check record budget")
  }
  @sort.validate_selector(selector) catch {
    _ => return Err("invalid key selector")
  }
  Ok(Check({ input_path: input, config, selector, }))
}

///|
fn parse_resume(args : Array[String]) -> Result[Command, String] {
  if args.length() != 3 && args.length() != 4 {
    return Err("resume requires MANIFEST and optional --force")
  }
  let replace = args.length() == 4 && args[3] == "--force"
  if args.length() == 4 && !replace {
    return Err("unknown resume option: " + args[3])
  }
  Ok(Resume(args[2], replace))
}

///|
fn parse_sort(args : Array[String]) -> Result[Command, String] {
  if args.length() < 4 {
    return Err("sort requires INPUT and OUTPUT")
  }
  let input = args[2]
  let output = args[3]
  let mut memory = 8 * 1024 * 1024
  let mut max_open = 32
  let mut max_record = 1024 * 1024
  let mut order = @sort.Ascending
  let mut key_kind = @sort.TextKey
  let mut selector = @sort.WholeRecord
  let mut work = output + ".moon-sort-work"
  let mut replace = false
  let mut selector_set = false
  let mut index = 4
  while index < args.length() {
    match args[index] {
      "--memory-bytes" => {
        guard index + 1 < args.length() else {
          return Err("--memory-bytes requires a value")
        }
        memory = match parse_int(args[index + 1]) {
          Ok(value) => value
          Err(message) => return Err(message)
        }
        index += 2
      }
      "--max-open-runs" => {
        guard index + 1 < args.length() else {
          return Err("--max-open-runs requires a value")
        }
        max_open = match parse_int(args[index + 1]) {
          Ok(value) => value
          Err(message) => return Err(message)
        }
        index += 2
      }
      "--max-record-bytes" => {
        guard index + 1 < args.length() else {
          return Err("--max-record-bytes requires a value")
        }
        max_record = match parse_int(args[index + 1]) {
          Ok(value) => value
          Err(message) => return Err(message)
        }
        index += 2
      }
      "--work-dir" => {
        guard index + 1 < args.length() else {
          return Err("--work-dir requires a value")
        }
        work = args[index + 1]
        index += 2
      }
      "--descending" => {
        order = @sort.Descending
        index += 1
      }
      "--numeric" => {
        key_kind = @sort.IntegerKey
        index += 1
      }
      "--force" => {
        replace = true
        index += 1
      }
      "--field-index" => {
        if selector_set {
          return Err("only one key selector may be specified")
        }
        guard index + 1 < args.length() else {
          return Err("--field-index requires a zero-based index")
        }
        let field_index = match parse_int(args[index + 1]) {
          Ok(value) => value
          Err(message) => return Err(message)
        }
        selector = @sort.DelimitedField(index=field_index, delimiter="\t")
        selector_set = true
        index += 2
      }
      "--json-field" => {
        if selector_set {
          return Err("only one key selector may be specified")
        }
        guard index + 1 < args.length() else {
          return Err("--json-field requires a top-level field name")
        }
        selector = @sort.JsonField(args[index + 1])
        selector_set = true
        index += 2
      }
      "--csv-field" => {
        if selector_set {
          return Err("only one key selector may be specified")
        }
        guard index + 1 < args.length() else {
          return Err("--csv-field requires a zero-based index")
        }
        let field_index = match parse_int(args[index + 1]) {
          Ok(value) => value
          Err(message) => return Err(message)
        }
        selector = @sort.CsvField(index=field_index, delimiter=',')
        selector_set = true
        index += 2
      }
      "--csv-delimiter" => {
        guard index + 1 < args.length() else {
          return Err("--csv-delimiter requires one character")
        }
        guard selector is @sort.CsvField(index=field_index, ..) else {
          return Err("--csv-delimiter requires --csv-field first")
        }
        let chars = args[index + 1].to_array()
        if chars.length() != 1 {
          return Err("--csv-delimiter requires exactly one character")
        }
        selector = @sort.CsvField(index=field_index, delimiter=chars[0])
        index += 2
      }
      "--delimiter" => {
        guard index + 1 < args.length() else {
          return Err("--delimiter requires a value")
        }
        guard selector is @sort.DelimitedField(index=field_index, ..) else {
          return Err("--delimiter requires --field-index first")
        }
        let delimiter = if args[index + 1] == "tab" {
          "\t"
        } else {
          args[index + 1]
        }
        selector = @sort.DelimitedField(index=field_index, delimiter~)
        index += 2
      }
      value => return Err("unknown sort option: " + value)
    }
  }
  let config = @sort.SortConfig::new(
    order~,
    key_kind~,
    memory_budget_bytes=memory,
    max_open_runs=max_open,
    max_record_bytes=max_record,
  ) catch {
    _ => return Err("invalid resource budget")
  }
  @sort.validate_selector(selector) catch {
    _ => return Err("invalid key selector")
  }
  Ok(
    Sort({
      input_path: input,
      output_path: output,
      work_directory: work,
      config,
      selector,
      replace_output: replace,
    }),
  )
}

///|
fn parse_int(text : String) -> Result[Int, String] {
  try @string.parse_int(text) catch {
    _ => Err("expected an integer, got: " + text)
  } noraise {
    value => Ok(value)
  }
}

///|
async fn fail(code : String, message : String, status : Int) -> Unit {
  @stdio.stderr.write("MOON_EXTERNAL_SORT_" + code + ": " + message + "\n") catch {
    _ => ()
  }
  process_exit(status)
}

///|
fn usage() -> String {
  (
    #|MoonExternalSort — stable bounded-memory external sorting
    #|
    #|Usage:
    #|  moon-external-sort sort INPUT OUTPUT [OPTIONS]
    #|  moon-external-sort check INPUT [KEY OPTIONS]
    #|  moon-external-sort resume MANIFEST [--force]
    #|  moon-external-sort version
    #|
    #|Sort options:
    #|  --memory-bytes N       Run-building record budget (default 8388608)
    #|  --max-open-runs N      merge fan-in / file limit (default 32)
    #|  --max-record-bytes N   reject larger input records (default 1048576)
    #|  --descending           reverse Sort Key order; equal keys stay stable
    #|  --numeric              parse selected keys as signed 64-bit integers
    #|  --field-index N        select zero-based TSV field
    #|  --delimiter TEXT       delimiter for --field-index; "tab" means TAB
    #|  --json-field NAME      select a top-level scalar JSONL field
    #|  --csv-field N          select zero-based quoted CSV field
    #|  --csv-delimiter CHAR   set CSV delimiter after --csv-field
    #|  --work-dir PATH        recovery workspace (default OUTPUT.moon-sort-work)
    #|  --force                replace an existing output atomically
    #|
    #|Check accepts --max-record-bytes and the same key/order selectors.
    #|
    #|Exit: 0 success, 2 usage/config, 3 existing path, 4 invalid input,
    #|      5 missing artifact, 6 corrupt recovery state, 7 host I/O,
    #|      8 input is not sorted.
    #|
  )
}
