///|
test "run codec round-trips control characters and Unicode" {
  let original : SortRecord = {
    key: TextValue("键\t\\"),
    input_position: 42L,
    payload: "值\twith\\slashes\r",
  }
  assert_eq(decode_run_record(encode_run_record(original)), original)
}

///|
test "run codec round-trips signed integer keys" {
  let original : SortRecord = {
    key: IntegerValue(-9223372036854775807L),
    input_position: 3L,
    payload: "minimum-ish",
  }
  assert_eq(decode_run_record(encode_run_record(original)), original)
}

///|
test "run codec rejects negative input positions" {
  try
    ignore(
      decode_run_record(
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
