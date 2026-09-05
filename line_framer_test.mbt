///|
test "line framer preserves empty lines and chunk boundaries" {
  let framer = LineFramer::new(16)
  let first = framer.push(b"a\n\npar")
  let second = framer.push(b"tial\nz")
  assert_eq(first, [b"a", b""])
  assert_eq(second, [b"partial"])
  guard framer.finish() is Some(last) else { fail("expected final line") }
  assert_eq(last, b"z")
}

///|
test "line framer rejects a record before allocating beyond its limit" {
  let framer = LineFramer::new(4)
  ignore(framer.push(b"1234"))
  assert_eq(framer.pending_bytes(), 4)
  try ignore(framer.push(b"5")) catch {
    RecordTooLarge(actual=5, limit=4) => ()
    _ => fail("unexpected SortError variant")
  } noraise {
    _ => fail("expected RecordTooLarge")
  }
}

///|
test "trailing newline does not invent another record" {
  let framer = LineFramer::new(8)
  assert_eq(framer.push(b"x\n"), [b"x"])
  assert_eq(framer.finish(), None)
}
