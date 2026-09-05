///|
test "CSV parser accepts plain and empty fields" {
  assert_eq(parse_csv_record("a,b,c"), ["a", "b", "c"])
  assert_eq(parse_csv_record(",,"), ["", "", ""])
  assert_eq(parse_csv_record(""), [""])
  assert_eq(parse_csv_record("a,"), ["a", ""])
}

///|
test "CSV parser decodes quoted delimiters and doubled quotes" {
  assert_eq(parse_csv_record("alpha,\"bravo,charlie\",\"say \"\"hello\"\"\""), [
    "alpha", "bravo,charlie", "say \"hello\"",
  ])
  assert_eq(parse_csv_record("\"\""), [""])
  assert_eq(parse_csv_record("\"a\"\"b\""), ["a\"b"])
}

///|
test "CSV parser supports custom dialects" {
  let dialect = CsvDialect::new(delimiter=';', quote='\'')
  assert_eq(parse_csv_record("one;'two;three';'it''s'", dialect~), [
    "one", "two;three", "it's",
  ])
}

///|
test "CSV parser rejects malformed quoting" {
  try parse_csv_record("a,\"missing") |> ignore catch {
    MalformedCsv(offset~, message~) => {
      assert_eq(offset, 10)
      assert_eq(message, "unterminated quoted field")
    }
    _ => fail("unexpected CSV failure")
  } noraise {
    _ => fail("expected unterminated quote")
  }
  try parse_csv_record("a,b\"c") |> ignore catch {
    MalformedCsv(offset~, ..) => assert_eq(offset, 3)
    _ => fail("unexpected CSV failure")
  } noraise {
    _ => fail("expected quote placement failure")
  }
  try parse_csv_record("\"a\"x") |> ignore catch {
    MalformedCsv(offset~, ..) => assert_eq(offset, 3)
    _ => fail("unexpected CSV failure")
  } noraise {
    _ => fail("expected trailing character failure")
  }
}

///|
test "CSV dialect validation rejects ambiguous syntax" {
  try CsvDialect::new(delimiter=',', quote=',') |> ignore catch {
    InvalidDialect(_) => ()
    _ => fail("unexpected dialect failure")
  } noraise {
    _ => fail("expected invalid dialect")
  }
  try CsvDialect::new(delimiter='\n') |> ignore catch {
    InvalidDialect(_) => ()
    _ => fail("unexpected dialect failure")
  } noraise {
    _ => fail("expected invalid delimiter")
  }
}

///|
test "CSV selector reports missing fields" {
  assert_eq(select_csv_field("a,\"b,c\",d", 1), "b,c")
  try select_csv_field("a,b", 2) |> ignore catch {
    CsvFieldMissing(index~, available~) => {
      assert_eq(index, 2)
      assert_eq(available, 2)
    }
    _ => fail("unexpected selector failure")
  } noraise {
    _ => fail("expected missing field")
  }
}

///|
test "CSV encoder minimally quotes fields" {
  assert_eq(encode_csv_field("plain"), "plain")
  assert_eq(encode_csv_field(""), "\"\"")
  assert_eq(encode_csv_field("a,b"), "\"a,b\"")
  assert_eq(encode_csv_field("a\"b"), "\"a\"\"b\"")
  assert_eq(
    encode_csv_record(["alpha", "b,c", "say \"hello\""]),
    "alpha,\"b,c\",\"say \"\"hello\"\"\"",
  )
}

///|
test "CSV codec round trips representative records" {
  let fixtures = [
    ["a", "b", "c"],
    ["", "", ""],
    ["comma,value", "quote\"value", "plain"],
    ["雪", "月亮", "line without newline"],
  ]
  for fields in fixtures {
    assert_eq(parse_csv_record(encode_csv_record(fields)), fields)
  }
}
