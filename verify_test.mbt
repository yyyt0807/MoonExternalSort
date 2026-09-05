///|
test "stream verifier accepts ascending text" {
  let verifier = SortednessVerifier::new(SortConfig::new())
  verifier.push("alpha", "alpha")
  verifier.push("bravo-1", "bravo")
  verifier.push("bravo-2", "bravo")
  verifier.push("charlie", "charlie")
  let report = verifier.report()
  assert_true(report.is_sorted())
  assert_eq(report.records, 4L)
  assert_eq(report.equal_adjacent_keys, 1L)
}

///|
test "stream verifier reports first ascending violation" {
  let verifier = SortednessVerifier::new(SortConfig::new())
  verifier.push("a", "a")
  verifier.push("c", "c")
  verifier.push("b", "b")
  verifier.push("a-later", "a")
  let report = verifier.report()
  guard report.violation is Some(violation) else { fail("expected violation") }
  assert_eq(violation.previous_index, 1L)
  assert_eq(violation.current_index, 2L)
  assert_eq(violation.previous_key, TextValue("c"))
  assert_eq(violation.current_key, TextValue("b"))
}

///|
test "stream verifier supports descending integers" {
  let verifier = SortednessVerifier::new(
    SortConfig::new(order=Descending, key_kind=IntegerKey),
  )
  for value in ["10", "10", "2", "0", "-4"] {
    verifier.push(value, value)
  }
  assert_true(verifier.report().is_sorted())
}

///|
test "stream verifier finds descending violation" {
  let verifier = SortednessVerifier::new(
    SortConfig::new(order=Descending, key_kind=IntegerKey),
  )
  verifier.push("10", "10")
  verifier.push("2", "2")
  verifier.push("3", "3")
  guard verifier.report().violation is Some(violation) else {
    fail("expected violation")
  }
  assert_eq(violation.previous_index, 1L)
  assert_eq(violation.current_index, 2L)
}

///|
test "record verifier detects unstable equal keys" {
  let verifier = SortednessVerifier::new(SortConfig::new())
  verifier.push_record({
    key: TextValue("same"),
    input_position: 5L,
    payload: "later",
  })
  verifier.push_record({
    key: TextValue("same"),
    input_position: 2L,
    payload: "earlier",
  })
  guard verifier.report().violation is Some(violation) else {
    fail("expected stability violation")
  }
  assert_eq(violation.previous_key, TextValue("same"))
  assert_eq(violation.current_key, TextValue("same"))
}

///|
test "empty and singleton streams are sorted" {
  let empty = SortednessVerifier::new(SortConfig::new())
  assert_true(empty.report().is_sorted())
  let singleton = SortednessVerifier::new(SortConfig::new())
  singleton.push("only", "only")
  assert_true(singleton.report().is_sorted())
}

///|
test "verifier propagates key and size failures" {
  let numeric = SortednessVerifier::new(
    SortConfig::new(key_kind=IntegerKey, max_record_bytes=16),
  )
  try numeric.push("payload", "not-number") catch {
    InvalidKey(_) => ()
    _ => fail("unexpected key failure")
  } noraise {
    _ => fail("expected invalid key")
  }
  let bounded = SortednessVerifier::new(
    SortConfig::new(memory_budget_bytes=256, max_record_bytes=4),
  )
  try bounded.push("12345", "x") catch {
    RecordTooLarge(actual~, limit~) => {
      assert_eq(actual, 5)
      assert_eq(limit, 4)
    }
    _ => fail("unexpected size failure")
  } noraise {
    _ => fail("expected record limit")
  }
}
