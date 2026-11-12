///|
test "run codec round-trips control characters and Unicode" {
  let original : @external-sort.SortRecord = {
    key: TextValue("键\t\\"),
    input_position: 42L,
    payload: "值\twith\\slashes\r",
  }
  assert_eq(
    @external-sort.decode_run_record(@external-sort.encode_run_record(original)),
    original,
  )
}

///|
test "run codec round-trips signed integer keys" {
  let original : @external-sort.SortRecord = {
    key: IntegerValue(-9223372036854775807L),
    input_position: 3L,
    payload: "minimum-ish",
  }
  assert_eq(
    @external-sort.decode_run_record(@external-sort.encode_run_record(original)),
    original,
  )
}

///|
test "run codec round-trips arbitrary precision decimal keys" {
  let original : @external-sort.SortRecord = {
    key: DecimalValue(
      @external-sort.parse_decimal_key("-9007199254740992.0000000000000001"),
    ),
    input_position: 7L,
    payload: "exact decimal",
  }
  let encoded = @external-sort.encode_run_record(original)
  assert_true(encoded.contains("\"kind\":\"decimal\""))
  assert_eq(@external-sort.decode_run_record(encoded), original)
}

///|
test "run codec rejects negative input positions" {
  try
    ignore(
      @external-sort.decode_run_record(
        (
          #|{"kind":"text","key":"x","position":-1,"payload":"x"}
        ),
      ),
    )
  catch {
    MalformedRun(_) => ()
    _ => fail("unexpected SortError variant")
  } noraise {
    _ => fail("expected MalformedRun")
  }
}
