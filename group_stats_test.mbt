///|
test "group counter summarizes stable ascending text" {
  let counter = SortedGroupCounter::new(
    SortConfig::new(memory_budget_bytes=1024, max_record_bytes=128),
  )
  for value in ["a", "a", "a", "b", "c", "c", "d"] {
    counter.push(value, value)
  }
  let stats = counter.finish()
  assert_true(stats.is_sorted())
  assert_eq(stats.records, 7L)
  assert_eq(stats.distinct_keys, 4L)
  assert_eq(stats.singleton_groups, 2L)
  assert_eq(stats.repeated_groups, 2L)
  assert_eq(stats.largest_group_records, 3L)
  assert_eq(stats.duplicate_records(), 3L)
  assert_eq(stats.first_key, Some(TextValue("a")))
  assert_eq(stats.last_key, Some(TextValue("d")))
  assert_eq(stats.average_group_size(), 1.75)
}

///|
test "empty group statistics are defined" {
  let counter = SortedGroupCounter::new(SortConfig::new())
  let stats = counter.finish()
  assert_true(stats.is_sorted())
  assert_eq(stats.records, 0L)
  assert_eq(stats.distinct_keys, 0L)
  assert_eq(stats.singleton_groups, 0L)
  assert_eq(stats.repeated_groups, 0L)
  assert_eq(stats.largest_group_records, 0L)
  assert_eq(stats.first_key, None)
  assert_eq(stats.last_key, None)
  assert_eq(stats.average_group_size(), 0.0)
}

///|
test "singleton group is counted when finishing" {
  let counter = SortedGroupCounter::new(
    SortConfig::new(memory_budget_bytes=256, max_record_bytes=64),
  )
  counter.push("only", "only")
  let stats = counter.finish()
  assert_eq(stats.distinct_keys, 1L)
  assert_eq(stats.singleton_groups, 1L)
  assert_eq(stats.repeated_groups, 0L)
  assert_eq(stats.largest_group_records, 1L)
}

///|
test "descending decimal groups preserve exact equality" {
  let counter = SortedGroupCounter::new(
    SortConfig::new(
      order=Descending,
      key_kind=DecimalKey,
      memory_budget_bytes=512,
      max_record_bytes=128,
    ),
  )
  for value in ["10.0", "10", "2.50", "2.5", "-1"] {
    counter.push(value, value)
  }
  let stats = counter.finish()
  assert_true(stats.is_sorted())
  assert_eq(stats.records, 5L)
  assert_eq(stats.distinct_keys, 3L)
  assert_eq(stats.repeated_groups, 2L)
  assert_eq(stats.singleton_groups, 1L)
  assert_eq(stats.largest_group_records, 2L)
}

///|
test "group counter retains first order violation" {
  let counter = SortedGroupCounter::new(
    SortConfig::new(
      key_kind=IntegerKey,
      memory_budget_bytes=512,
      max_record_bytes=64,
    ),
  )
  for value in ["1", "3", "2", "2", "4"] {
    counter.push(value, value)
  }
  let stats = counter.finish()
  assert_false(stats.is_sorted())
  assert_eq(stats.distinct_keys, 4L)
  assert_eq(stats.repeated_groups, 1L)
  guard stats.verification.violation is Some(violation) else {
    fail("expected order violation")
  }
  assert_eq(violation.previous_index, 1L)
  assert_eq(violation.current_index, 2L)
}

///|
test "record input detects unstable equal positions" {
  let counter = SortedGroupCounter::new(SortConfig::new())
  counter.push_record({
    key: TextValue("same"),
    input_position: 9L,
    payload: "later",
  })
  counter.push_record({
    key: TextValue("same"),
    input_position: 3L,
    payload: "earlier",
  })
  let stats = counter.finish()
  assert_false(stats.is_sorted())
  assert_eq(stats.distinct_keys, 1L)
  assert_eq(stats.repeated_groups, 1L)
  assert_eq(stats.largest_group_records, 2L)
}

///|
test "group counter validates lifecycle and record size" {
  try
    SortedGroupCounter::new(SortConfig::new(), start_position=-1L) |> ignore
  catch {
    InvalidConfig(_) => ()
    _ => fail("unexpected start position failure")
  } noraise {
    _ => fail("expected invalid start position")
  }
  let counter = SortedGroupCounter::new(
    SortConfig::new(memory_budget_bytes=256, max_record_bytes=4),
  )
  try counter.push("12345", "1") catch {
    RecordTooLarge(actual~, limit~) => {
      assert_eq(actual, 5)
      assert_eq(limit, 4)
    }
    _ => fail("unexpected record failure")
  } noraise {
    _ => fail("expected record limit")
  }
  counter.push("one", "1")
  ignore(counter.finish())
  try counter.finish() |> ignore catch {
    InvalidConfig(_) => ()
    _ => fail("unexpected finish failure")
  } noraise {
    _ => fail("expected repeated finish rejection")
  }
  try counter.push("two", "2") catch {
    InvalidConfig(_) => ()
    _ => fail("unexpected lifecycle failure")
  } noraise {
    _ => fail("expected push-after-finish rejection")
  }
}
