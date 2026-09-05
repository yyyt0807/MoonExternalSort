///|
async test "native check reports sorted CSV input" {
  let root = "_build/external_sort_check_sorted"
  if @fs.exists(root) {
    @fs.rmdir(root, recursive=true)
  }
  @fs.mkdir(root, recursive=true)
  let input = root + "/sorted.csv"
  @fs.write_file(
    input,
    "1,alpha\n1,bravo\n2,charlie\n10,delta\n",
    create_mode=CreateOrTruncate,
  )
  let report = check_file({
    input_path: input,
    config: @sort.SortConfig::new(
      key_kind=@sort.IntegerKey,
      memory_budget_bytes=256,
      max_record_bytes=128,
    ),
    selector: @sort.CsvField(index=0, delimiter=','),
  })
  assert_true(report.sorted)
  assert_eq(report.records, 4L)
  assert_eq(report.equal_adjacent_keys, 1L)
  assert_eq(report.previous_index, None)
  @fs.rmdir(root, recursive=true)
}

///|
async test "native check returns the first disorder diagnostic" {
  let root = "_build/external_sort_check_unsorted"
  if @fs.exists(root) {
    @fs.rmdir(root, recursive=true)
  }
  @fs.mkdir(root, recursive=true)
  let input = root + "/unsorted.tsv"
  @fs.write_file(
    input,
    "1\tfirst\n3\tthird\n2\tsecond\n4\tfourth\n",
    create_mode=CreateOrTruncate,
  )
  let report = check_file({
    input_path: input,
    config: @sort.SortConfig::new(
      key_kind=@sort.IntegerKey,
      memory_budget_bytes=256,
      max_record_bytes=128,
    ),
    selector: @sort.DelimitedField(index=0, delimiter="\t"),
  })
  assert_false(report.sorted)
  assert_eq(report.records, 4L)
  assert_eq(report.previous_index, Some(1L))
  assert_eq(report.current_index, Some(2L))
  assert_eq(report.previous_key, Some(@sort.IntegerValue(3L)))
  assert_eq(report.current_key, Some(@sort.IntegerValue(2L)))
  let json = check_report_json(report)
  assert_true(json.contains("\"sorted\":false"))
  assert_true(json.contains("\"previousIndex\":1"))
  @fs.rmdir(root, recursive=true)
}

///|
async test "native check accepts empty and unterminated files" {
  let root = "_build/external_sort_check_edges"
  if @fs.exists(root) {
    @fs.rmdir(root, recursive=true)
  }
  @fs.mkdir(root, recursive=true)
  let empty = root + "/empty.txt"
  @fs.write_file(empty, "", create_mode=CreateOrTruncate)
  let empty_report = check_file({
    input_path: empty,
    config: @sort.SortConfig::new(),
    selector: @sort.WholeRecord,
  })
  assert_true(empty_report.sorted)
  assert_eq(empty_report.records, 0L)
  let single = root + "/single.txt"
  @fs.write_file(single, "only", create_mode=CreateOrTruncate)
  let single_report = check_file({
    input_path: single,
    config: @sort.SortConfig::new(),
    selector: @sort.WholeRecord,
  })
  assert_true(single_report.sorted)
  assert_eq(single_report.records, 1L)
  @fs.rmdir(root, recursive=true)
}
