///|
fn text_record(key : String, position : Int64, payload : String) -> SortRecord {
  { key: TextValue(key), input_position: position, payload, }
}

///|
test "k-way merge preserves global ordering and stability" {
  let runs = [
    [text_record("a", 0L, "a0"), text_record("c", 3L, "c3")],
    [text_record("a", 1L, "a1"), text_record("b", 2L, "b2")],
    [],
  ]
  let merged = merge_sorted_runs(runs, Ascending)
  assert_eq(merged.map(record => record.payload), ["a0", "a1", "b2", "c3"])
}

///|
test "k-way merge supports descending keys without reversing stable ties" {
  let runs = [
    [text_record("z", 0L, "z0"), text_record("a", 2L, "a2")],
    [text_record("z", 1L, "z1"), text_record("b", 3L, "b3")],
  ]
  let merged = merge_sorted_runs(runs, Descending)
  assert_eq(merged.map(record => record.payload), ["z0", "z1", "b3", "a2"])
}

///|
test "merge result matches a directly sorted reference" {
  let records = [
    text_record("d", 0L, "d"),
    text_record("a", 1L, "a1"),
    text_record("c", 2L, "c"),
    text_record("a", 3L, "a3"),
    text_record("b", 4L, "b"),
  ]
  let runs = [
    records[0:2].to_owned(),
    records[2:4].to_owned(),
    records[4:].to_owned(),
  ]
  for run in runs {
    run.sort_by((a, b) => compare_records(a, b, Ascending))
  }
  let reference = records.copy()
  reference.sort_by((a, b) => compare_records(a, b, Ascending))
  assert_eq(merge_sorted_runs(runs, Ascending), reference)
}
