///|
test "run builder spills before exceeding its retained budget" {
  let config = SortConfig::new(memory_budget_bytes=256, max_record_bytes=200)
  let builder = RunBuilder::new(config)
  let c = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  let a = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let b = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  assert_eq(builder.push(c, "c"), None)
  assert_eq(builder.push(a, "a"), None)
  let completed = builder.push(b, "b")
  guard completed is Some(run) else { fail("expected a completed run") }
  assert_eq(run.map(record => record.payload), [a, c])
  assert_true(builder.retained_bytes() <= config.memory_budget_bytes)
  guard builder.finish() is Some(last) else { fail("expected final run") }
  assert_eq(last.map(record => record.payload), [b])
}

///|
test "run builder is stable for equal keys" {
  let config = SortConfig::new(memory_budget_bytes=1024, max_record_bytes=512)
  let builder = RunBuilder::new(config)
  ignore(builder.push("first", "x"))
  ignore(builder.push("second", "x"))
  ignore(builder.push("third", "x"))
  guard builder.finish() is Some(run) else { fail("expected final run") }
  assert_eq(run.map(record => record.payload), ["first", "second", "third"])
}

///|
test "oversized input record is rejected" {
  let config = SortConfig::new(memory_budget_bytes=256, max_record_bytes=4)
  let builder = RunBuilder::new(config)
  try ignore(builder.push("12345", "x")) catch {
    RecordTooLarge(actual=5, limit=4) => ()
    _ => fail("unexpected SortError variant")
  } noraise {
    _ => fail("expected RecordTooLarge")
  }
}
