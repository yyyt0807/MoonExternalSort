///|
async test "native engine creates multiple Runs and publishes stable output" {
  let root = "_build/external_sort_native_text"
  if @fs.exists(root) {
    @fs.rmdir(root, recursive=true)
  }
  @fs.mkdir(root, recursive=true)
  let input = root + "/input.txt"
  let output = root + "/output.txt"
  let work = root + "/work"
  @fs.write_file(
    input,
    "c payload-cccccccccccccccccccccccccccccccccccc\n" +
    "a first-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n" +
    "a second-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n" +
    "b payload-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n",
    create_mode=CreateOrTruncate,
  )
  let report = sort_file({
    input_path: input,
    output_path: output,
    work_directory: work,
    config: @sort.SortConfig::new(
      memory_budget_bytes=256,
      max_open_runs=2,
      max_record_bytes=128,
    ),
    selector: @sort.DelimitedField(index=0, delimiter=" "),
    replace_output: false,
  })
  assert_eq(report.input_records, 4L)
  assert_true(report.initial_runs >= 2)
  assert_eq(
    @fs.read_file(output).text(),
    "a first-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n" +
    "a second-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n" +
    "b payload-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n" +
    "c payload-cccccccccccccccccccccccccccccccccccc\n",
  )
  let manifest = @sort.decode_manifest(
    @fs.read_file(report.manifest_path).text(),
  )
  assert_eq(manifest.phase, @sort.Published)
  @fs.rmdir(root, recursive=true)
}

///|
async test "JSONL scalar selector supports descending signed integer keys" {
  let root = "_build/external_sort_native_jsonl"
  if @fs.exists(root) {
    @fs.rmdir(root, recursive=true)
  }
  @fs.mkdir(root, recursive=true)
  let input = root + "/input.jsonl"
  let output = root + "/output.jsonl"
  @fs.write_file(
    input,
    "{\"priority\":-2,\"id\":\"low\"}\n" +
    "{\"priority\":10,\"id\":\"high-1\"}\n" +
    "{\"priority\":10,\"id\":\"high-2\"}\n",
    create_mode=CreateOrTruncate,
  )
  ignore(
    sort_file({
      input_path: input,
      output_path: output,
      work_directory: root + "/work",
      config: @sort.SortConfig::new(
        order=@sort.Descending,
        key_kind=@sort.IntegerKey,
        memory_budget_bytes=512,
        max_open_runs=2,
        max_record_bytes=256,
      ),
      selector: @sort.JsonField("priority"),
      replace_output: false,
    }),
  )
  assert_eq(
    @fs.read_file(output).text(),
    "{\"priority\":10,\"id\":\"high-1\"}\n" +
    "{\"priority\":10,\"id\":\"high-2\"}\n" +
    "{\"priority\":-2,\"id\":\"low\"}\n",
  )
  @fs.rmdir(root, recursive=true)
}

///|
async test "CSV selector respects quoted delimiters and stable duplicate keys" {
  let root = "_build/external_sort_native_csv"
  if @fs.exists(root) {
    @fs.rmdir(root, recursive=true)
  }
  @fs.mkdir(root, recursive=true)
  let input = root + "/input.csv"
  let output = root + "/output.csv"
  @fs.write_file(
    input,
    "3,plain,third\n" +
    "1,\"quoted,value\",first-a\n" +
    "1,\"say \"\"hello\"\"\",first-b\n" +
    "2,middle,second\n",
    create_mode=CreateOrTruncate,
  )
  let report = sort_file({
    input_path: input,
    output_path: output,
    work_directory: root + "/work",
    config: @sort.SortConfig::new(
      key_kind=@sort.IntegerKey,
      memory_budget_bytes=512,
      max_open_runs=2,
      max_record_bytes=128,
    ),
    selector: @sort.CsvField(index=0, delimiter=','),
    replace_output: false,
  })
  assert_eq(report.input_records, 4L)
  assert_eq(
    @fs.read_file(output).text(),
    "1,\"quoted,value\",first-a\n" +
    "1,\"say \"\"hello\"\"\",first-b\n" +
    "2,middle,second\n" +
    "3,plain,third\n",
  )
  @fs.rmdir(root, recursive=true)
}

///|
async test "native engine orders decimal keys without floating point loss" {
  let root = "_build/external_sort_native_decimal"
  if @fs.exists(root) {
    @fs.rmdir(root, recursive=true)
  }
  @fs.mkdir(root, recursive=true)
  let input = root + "/prices.tsv"
  let output = root + "/prices.sorted.tsv"
  @fs.write_file(
    input,
    "9007199254740992.0000000000000002\tsecond\n" +
    "-0.01\tnegative\n" +
    "9007199254740992.0000000000000001\tfirst\n" +
    "1.20\tequal-a\n" +
    "1.2\tequal-b\n",
    create_mode=CreateOrTruncate,
  )
  ignore(
    sort_file({
      input_path: input,
      output_path: output,
      work_directory: root + "/work",
      config: @sort.SortConfig::new(
        key_kind=@sort.DecimalKey,
        memory_budget_bytes=512,
        max_open_runs=2,
        max_record_bytes=128,
      ),
      selector: @sort.DelimitedField(index=0, delimiter="\t"),
      replace_output: false,
    }),
  )
  assert_eq(
    @fs.read_file(output).text(),
    "-0.01\tnegative\n" +
    "1.20\tequal-a\n" +
    "1.2\tequal-b\n" +
    "9007199254740992.0000000000000001\tfirst\n" +
    "9007199254740992.0000000000000002\tsecond\n",
  )
  @fs.rmdir(root, recursive=true)
}

///|
async test "resume consumes only Runs committed by the manifest" {
  let root = "_build/external_sort_native_resume"
  if @fs.exists(root) {
    @fs.rmdir(root, recursive=true)
  }
  @fs.mkdir(root, recursive=true)
  let run0 = root + "/pass-0-run-0.run"
  let run1 = root + "/pass-0-run-1.run"
  let records0 = [
    @sort.SortRecord::{
      key: @sort.TextValue("a"),
      input_position: 1L,
      payload: "a",
    },
    @sort.SortRecord::{
      key: @sort.TextValue("c"),
      input_position: 0L,
      payload: "c",
    },
  ]
  let records1 = [
    @sort.SortRecord::{
      key: @sort.TextValue("b"),
      input_position: 2L,
      payload: "b",
    },
  ]
  @fs.write_file(
    run0,
    records0.map(record => @sort.encode_run_record(record)).join("\n") + "\n",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    run1,
    records1.map(record => @sort.encode_run_record(record)).join("\n") + "\n",
    create_mode=CreateOrTruncate,
  )
  let output = root + "/output.txt"
  let manifest_path = root + "/manifest.json"
  let manifest : @sort.JobManifest = {
    phase: @sort.RunsReady,
    input_path: root + "/unneeded-after-run-generation.txt",
    output_path: output,
    work_directory: root,
    config: @sort.SortConfig::new(
      memory_budget_bytes=512,
      max_open_runs=2,
      max_record_bytes=128,
    ),
    selector: @sort.WholeRecord,
    input_records: 3L,
    initial_run_count: 2,
    merge_pass: 0,
    runs: [{ path: run0, record_count: 2L, }, { path: run1, record_count: 1L, }],
  }
  @fs.write_file(
    manifest_path,
    @sort.encode_manifest(manifest),
    create_mode=CreateOrTruncate,
  )
  let report = resume_file(manifest_path)
  assert_true(report.recovered)
  assert_eq(@fs.read_file(output).text(), "a\nb\nc\n")
  @fs.rmdir(root, recursive=true)
}
