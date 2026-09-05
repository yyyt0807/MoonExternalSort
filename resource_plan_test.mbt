///|
test "capacity estimate distinguishes text and integer keys" {
  let text = estimate_run_capacity(
    SortConfig::new(
      key_kind=TextKey,
      memory_budget_bytes=1024,
      max_open_runs=4,
      max_record_bytes=128,
    ),
  )
  assert_eq(text.worst_case_record_bytes, 288L)
  assert_eq(text.records_per_run, 3L)
  assert_eq(text.conservative_merge_head_bytes, 1152L)
  assert_false(text.merge_heads_fit_run_budget)
  let integer = estimate_run_capacity(
    SortConfig::new(
      key_kind=IntegerKey,
      memory_budget_bytes=1024,
      max_open_runs=4,
      max_record_bytes=128,
    ),
  )
  assert_eq(integer.worst_case_record_bytes, 184L)
  assert_eq(integer.records_per_run, 5L)
  assert_eq(integer.conservative_merge_head_bytes, 736L)
  assert_true(integer.merge_heads_fit_run_budget)
}

///|
test "merge schedule reproduces a six-pass stress shape" {
  let schedule = build_merge_schedule(625L, 3)
  assert_eq(schedule.length(), 6)
  assert_eq(schedule.map(pass => (pass.input_runs, pass.output_runs)), [
    (625L, 209L),
    (209L, 70L),
    (70L, 24L),
    (24L, 8L),
    (8L, 3L),
    (3L, 1L),
  ])
  assert_eq(schedule[0].largest_group, 3)
  assert_eq(schedule[5].largest_group, 3)
}

///|
test "empty and singleton schedules need no merge" {
  assert_eq(build_merge_schedule(0L, 32), [])
  assert_eq(build_merge_schedule(1L, 32), [])
  let pair = build_merge_schedule(2L, 32)
  assert_eq(pair, [
    { pass: 1, input_runs: 2L, output_runs: 1L, largest_group: 2, },
  ])
}

///|
test "job estimate computes run count and payload IO lower bound" {
  let estimate = estimate_job(
    1000L,
    100000L,
    SortConfig::new(
      key_kind=IntegerKey,
      memory_budget_bytes=1024,
      max_open_runs=4,
      max_record_bytes=128,
    ),
  )
  assert_eq(estimate.average_payload_bytes, 100L)
  assert_eq(estimate.records_per_run, 6L)
  assert_eq(estimate.initial_runs, 167L)
  assert_eq(estimate.merge_passes, 4)
  assert_eq(estimate.minimum_payload_io_bytes, 1200000L)
  assert_eq(estimate.peak_payload_generation_bytes, 200000L)
  assert_false(estimate.saturated)
}

///|
test "job estimate rounds average and run divisions upward" {
  let estimate = estimate_job(
    3L,
    10L,
    SortConfig::new(
      key_kind=IntegerKey,
      memory_budget_bytes=256,
      max_open_runs=2,
      max_record_bytes=64,
    ),
  )
  assert_eq(estimate.average_payload_bytes, 4L)
  assert_eq(estimate.records_per_run, 4L)
  assert_eq(estimate.initial_runs, 1L)
  assert_eq(estimate.merge_passes, 0)
}

///|
test "empty job estimate is internally consistent" {
  let estimate = estimate_job(0L, 0L, SortConfig::new())
  assert_eq(estimate.average_payload_bytes, 0L)
  assert_eq(estimate.initial_runs, 0L)
  assert_eq(estimate.merge_passes, 0)
  assert_eq(estimate.minimum_payload_io_bytes, 0L)
  assert_eq(estimate.peak_payload_generation_bytes, 0L)
  assert_eq(estimate.schedule, [])
}

///|
test "resource planner validates impossible inputs" {
  try build_merge_schedule(-1L, 2) |> ignore catch {
    InvalidConfig(_) => ()
    _ => fail("unexpected schedule error")
  } noraise {
    _ => fail("expected negative run count rejection")
  }
  try build_merge_schedule(2L, 1) |> ignore catch {
    InvalidConfig(_) => ()
    _ => fail("unexpected fan-in error")
  } noraise {
    _ => fail("expected invalid fan-in rejection")
  }
  try estimate_job(-1L, 0L, SortConfig::new()) |> ignore catch {
    InvalidConfig(_) => ()
    _ => fail("unexpected record count error")
  } noraise {
    _ => fail("expected negative record count rejection")
  }
  try estimate_job(0L, 1L, SortConfig::new()) |> ignore catch {
    InvalidConfig(_) => ()
    _ => fail("unexpected empty byte count error")
  } noraise {
    _ => fail("expected inconsistent empty input rejection")
  }
}

///|
test "payload IO estimate saturates instead of wrapping" {
  let estimate = estimate_job(
    9223372036854775807L,
    9223372036854775807L,
    SortConfig::new(
      memory_budget_bytes=256,
      max_open_runs=2,
      max_record_bytes=64,
    ),
  )
  assert_eq(estimate.minimum_payload_io_bytes, 9223372036854775807L)
  assert_eq(estimate.peak_payload_generation_bytes, 9223372036854775807L)
  assert_true(estimate.saturated)
  assert_true(estimate.merge_passes > 0)
}

///|
test "resource estimate JSON exposes schedule and saturation" {
  let json = job_estimate_json(
    estimate_job(
      20L,
      200L,
      SortConfig::new(
        memory_budget_bytes=256,
        max_open_runs=2,
        max_record_bytes=64,
      ),
    ),
  )
  assert_true(json.contains("\"schemaVersion\":1"))
  assert_true(json.contains("\"inputRecords\":20"))
  assert_true(json.contains("\"schedule\":["))
  assert_true(json.contains("\"saturated\":false"))
  let parsed = @json.parse(json)
  guard parsed is Object(fields) else { fail("expected JSON object") }
  guard fields.get("inputRecords") is Some(Number(value, ..)) else {
    fail("expected numeric inputRecords")
  }
  assert_eq(value, 20.0)
}
