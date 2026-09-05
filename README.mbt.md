# yyyt0807/external-sort

Stable bounded-memory external sorting primitives for MoonBit.

```mbt check
///|
test {
  let config = SortConfig::new(memory_budget_bytes=1024, max_record_bytes=256)
  let builder = RunBuilder::new(config)
  ignore(builder.push("second", "b"))
  ignore(builder.push("first", "a"))
  guard builder.finish() is Some(run) else { fail("expected run") }
  assert_eq(run.map(record => record.payload), ["first", "second"])
}
```

The root package is portable. Native filesystem execution and recovery live in `yyyt0807/external-sort/adapter/native`; the executable is `cmd/moon-external-sort`.
