///|
test "decimal parser canonicalizes signs and zeros" {
  assert_eq(parse_decimal_key("00123.4500"), {
    negative: false,
    digits: "12345",
    scale: 2,
  })
  assert_eq(parse_decimal_key("-0.00100"), {
    negative: true,
    digits: "1",
    scale: 3,
  })
  assert_eq(parse_decimal_key("-000.000"), {
    negative: false,
    digits: "0",
    scale: 0,
  })
  assert_eq(parse_decimal_key("+.5"), {
    negative: false,
    digits: "5",
    scale: 1,
  })
  assert_eq(parse_decimal_key("5."), { negative: false, digits: "5", scale: 0, })
}

///|
test "decimal comparison is exact beyond floating point precision" {
  let a = parse_decimal_key("9007199254740992.0000000000000001")
  let b = parse_decimal_key("9007199254740992.0000000000000002")
  assert_true(compare_decimal_keys(a, b) < 0)
  assert_true(compare_decimal_keys(b, a) > 0)
  assert_eq(compare_decimal_keys(a, a), 0)
}

///|
test "decimal comparison aligns different scales" {
  assert_eq(
    compare_decimal_keys(parse_decimal_key("1.2"), parse_decimal_key("1.20")),
    0,
  )
  assert_true(
    compare_decimal_keys(parse_decimal_key("1.19"), parse_decimal_key("1.2")) <
    0,
  )
  assert_true(
    compare_decimal_keys(
      parse_decimal_key("0.0001"),
      parse_decimal_key("0.001"),
    ) <
    0,
  )
  assert_true(
    compare_decimal_keys(parse_decimal_key("100"), parse_decimal_key("99.999")) >
    0,
  )
}

///|
test "decimal comparison handles negatives" {
  assert_true(
    compare_decimal_keys(parse_decimal_key("-10"), parse_decimal_key("-2")) < 0,
  )
  assert_true(
    compare_decimal_keys(parse_decimal_key("-0.01"), parse_decimal_key("0")) < 0,
  )
  assert_true(
    compare_decimal_keys(parse_decimal_key("0"), parse_decimal_key("0.000")) ==
    0,
  )
}

///|
test "decimal canonical renderer round trips" {
  for
    text in [
      "0", "1", "-1", "123.45", "-0.001", "999999999999999999999999.0000001",
    ] {
    let value = parse_decimal_key(text)
    let canonical = value.to_canonical_string()
    assert_eq(parse_decimal_key(canonical), value)
  }
}

///|
test "decimal parser rejects unsupported forms" {
  for text in ["", "+", "-", ".", "1.2.3", "1e3", "NaN", " 1", "1 "] {
    try parse_decimal_key(text) |> ignore catch {
      InvalidKey(_) => ()
      _ => fail("unexpected decimal parse error")
    } noraise {
      _ => fail("expected invalid decimal: " + text)
    }
  }
}

///|
test "SortValue decimal order works in stable ascending and descending modes" {
  let ascending = RunBuilder::new(
    SortConfig::new(
      key_kind=DecimalKey,
      memory_budget_bytes=1024,
      max_record_bytes=128,
    ),
  )
  for value in ["1.20", "-2", "1.19", "1.2", "0.001"] {
    ignore(ascending.push(value, value))
  }
  guard ascending.finish() is Some(up) else { fail("expected decimal Run") }
  assert_eq(up.map(record => record.payload), [
    "-2", "0.001", "1.19", "1.20", "1.2",
  ])
  let descending = RunBuilder::new(
    SortConfig::new(
      order=Descending,
      key_kind=DecimalKey,
      memory_budget_bytes=1024,
      max_record_bytes=128,
    ),
  )
  for value in ["1.20", "-2", "1.19", "1.2", "0.001"] {
    ignore(descending.push(value, value))
  }
  guard descending.finish() is Some(down) else { fail("expected decimal Run") }
  assert_eq(down.map(record => record.payload), [
    "1.20", "1.2", "1.19", "0.001", "-2",
  ])
}
