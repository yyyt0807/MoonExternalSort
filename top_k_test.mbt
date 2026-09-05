///|
test "Top-K selects smallest text records stably" {
  let selector = TopKSelector::new(
    SortConfig::new(memory_budget_bytes=1024, max_record_bytes=128),
    4,
  )
  for
    pair in [
      ("delta", "d"),
      ("alpha-first", "a"),
      ("charlie", "c"),
      ("alpha-second", "a"),
      ("bravo", "b"),
      ("echo", "e"),
    ] {
    let (payload, key) = pair
    selector.push(payload, key)
  }
  let result = selector.finish()
  assert_eq(result.records.map(record => record.payload), [
    "alpha-first", "alpha-second", "bravo", "charlie",
  ])
  assert_eq(result.input_records, 6L)
  assert_eq(result.discarded_records, 2L)
  assert_true(result.retained_bytes > 0)
}

///|
test "Top-K selects greatest integers for descending output" {
  let selector = TopKSelector::new(
    SortConfig::new(
      order=Descending,
      key_kind=IntegerKey,
      memory_budget_bytes=1024,
      max_record_bytes=64,
    ),
    3,
  )
  for value in ["-4", "10", "2", "99", "10", "0"] {
    selector.push(value, value)
  }
  let result = selector.finish()
  assert_eq(result.records.map(record => record.payload), ["99", "10", "10"])
  assert_eq(result.records.map(record => record.input_position), [3L, 1L, 4L])
}

///|
test "Top-K zero limit validates input without retaining it" {
  let selector = TopKSelector::new(SortConfig::new(), 0)
  selector.push("one", "one")
  selector.push("two", "two")
  let result = selector.finish()
  assert_eq(result.records, [])
  assert_eq(result.input_records, 2L)
  assert_eq(result.discarded_records, 2L)
  assert_eq(result.retained_bytes, 0)
}

///|
test "Top-K returns all records when fewer than limit" {
  let selector = TopKSelector::new(SortConfig::new(), 10)
  selector.push("c", "c")
  selector.push("a", "a")
  selector.push("b", "b")
  let result = selector.finish()
  assert_eq(result.records.map(record => record.payload), ["a", "b", "c"])
  assert_eq(result.discarded_records, 0L)
}

///|
test "Top-K enforces aggregate selection budget" {
  let selector = TopKSelector::new(
    SortConfig::new(memory_budget_bytes=256, max_record_bytes=128),
    4,
  )
  selector.push("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "a")
  selector.push("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "b")
  selector.push("cccccccccccccccccccccccccccccccccccccccc", "c")
  try selector.push("dddddddddddddddddddddddddddddddddddddddd", "d") catch {
    SelectionBudgetExceeded(required~, limit~) => {
      assert_true(required > limit)
      assert_eq(limit, 256)
    }
    _ => fail("unexpected Top-K budget failure")
  } noraise {
    _ => fail("expected aggregate budget failure")
  }
}

///|
test "Top-K rejects invalid limits and repeated finish" {
  try TopKSelector::new(SortConfig::new(), -1) |> ignore catch {
    InvalidConfig(_) => ()
    _ => fail("unexpected invalid limit failure")
  } noraise {
    _ => fail("expected invalid limit")
  }
  let selector = TopKSelector::new(SortConfig::new(), 1)
  selector.push("one", "one")
  ignore(selector.finish())
  try selector.finish() |> ignore catch {
    InvalidConfig(_) => ()
    _ => fail("unexpected repeated finish failure")
  } noraise {
    _ => fail("expected repeated finish rejection")
  }
}

///|
test "Top-K result matches full reference sort" {
  let config = SortConfig::new(
    key_kind=IntegerKey,
    memory_budget_bytes=4096,
    max_record_bytes=64,
  )
  let selector = TopKSelector::new(config, 17)
  let reference : Array[SortRecord] = []
  for index = 0; index < 200; index = index + 1 {
    let value = (index * 73 + 19) % 41 - 20
    let text = value.to_string()
    selector.push(text + ":" + index.to_string(), text)
    reference.push({
      key: IntegerValue(value.to_int64()),
      input_position: index.to_int64(),
      payload: text + ":" + index.to_string(),
    })
  }
  reference.sort_by((left, right) => compare_records(left, right, Ascending))
  let expected = reference[0:17].to_owned()
  assert_eq(selector.finish().records, expected)
}
