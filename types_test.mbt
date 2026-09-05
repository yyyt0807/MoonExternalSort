///|
test "configuration rejects budgets that cannot hold one record" {
  try ignore(SortConfig::new(memory_budget_bytes=128)) catch {
    InvalidConfig(_) => ()
    _ => fail("unexpected SortError variant")
  } noraise {
    _ => fail("expected InvalidConfig")
  }
}

///|
test "integer keys use numeric rather than lexical order" {
  let left : SortRecord = {
    key: parse_key("10", IntegerKey),
    input_position: 0L,
    payload: "ten",
  }
  let right : SortRecord = {
    key: parse_key("2", IntegerKey),
    input_position: 1L,
    payload: "two",
  }
  assert_true(compare_records(left, right, Ascending) > 0)
  assert_true(compare_records(left, right, Descending) < 0)
}

///|
test "descending order preserves ascending input position for equal keys" {
  let earlier : SortRecord = {
    key: TextValue("same"),
    input_position: 7L,
    payload: "earlier",
  }
  let later : SortRecord = {
    key: TextValue("same"),
    input_position: 9L,
    payload: "later",
  }
  assert_true(compare_records(earlier, later, Descending) < 0)
}

///|
test "invalid signed integer is reported" {
  try ignore(parse_key("12x", IntegerKey)) catch {
    InvalidKey(_) => ()
    _ => fail("unexpected SortError variant")
  } noraise {
    _ => fail("expected InvalidKey")
  }
}
