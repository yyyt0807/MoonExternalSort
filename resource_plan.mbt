///|
/// Conservative record and merge-head capacity derived from a SortConfig.
pub(all) struct RunCapacityEstimate {
  worst_case_record_bytes : Int64
  records_per_run : Int64
  conservative_merge_head_bytes : Int64
  merge_heads_fit_run_budget : Bool
} derive(Debug, Eq)

///|
/// One row in a multi-pass merge schedule.
pub(all) struct MergePassEstimate {
  pass : Int
  input_runs : Int64
  output_runs : Int64
  largest_group : Int
} derive(Debug, Eq)

///|
/// Static planning result. Byte estimates describe original payload bytes;
/// internal JSONL escaping and host filesystem allocation are intentionally not
/// presented as exact values.
pub(all) struct JobEstimate {
  input_records : Int64
  input_payload_bytes : Int64
  average_payload_bytes : Int64
  records_per_run : Int64
  initial_runs : Int64
  merge_passes : Int
  minimum_payload_io_bytes : Int64
  peak_payload_generation_bytes : Int64
  schedule : Array[MergePassEstimate]
  saturated : Bool
} derive(Debug, Eq)

///|
/// Compute conservative record retention from configured maximum input size.
pub fn estimate_run_capacity(config : SortConfig) -> RunCapacityEstimate {
  let payload = config.max_record_bytes.to_int64()
  let worst_case_record_bytes = match config.key_kind {
    TextKey => saturating_add_i64(saturating_mul_i64(payload, 2L), 32L)
    IntegerKey => saturating_add_i64(payload, 56L)
    DecimalKey => saturating_add_i64(saturating_mul_i64(payload, 2L), 40L)
  }
  let records_per_run = maximum_i64(
    1L,
    config.memory_budget_bytes.to_int64() / worst_case_record_bytes,
  )
  let conservative_merge_head_bytes = saturating_mul_i64(
    worst_case_record_bytes,
    config.max_open_runs.to_int64(),
  )
  {
    worst_case_record_bytes,
    records_per_run,
    conservative_merge_head_bytes,
    merge_heads_fit_run_budget: conservative_merge_head_bytes <=
    config.memory_budget_bytes.to_int64(),
  }
}

///|
/// Build every pass needed to reduce `initial_runs` to one. The empty and
/// singleton cases need no merge passes.
pub fn build_merge_schedule(
  initial_runs : Int64,
  max_open_runs : Int,
) -> Array[MergePassEstimate] raise SortError {
  if initial_runs < 0L {
    raise InvalidConfig("initial_runs must not be negative")
  }
  if max_open_runs < 2 {
    raise InvalidConfig("max_open_runs must be at least 2")
  }
  let schedule : Array[MergePassEstimate] = []
  let fan_in = max_open_runs.to_int64()
  let mut input_runs = initial_runs
  let mut pass = 1
  while input_runs > 1L {
    let output_runs = ceil_div_i64(input_runs, fan_in)
    schedule.push({
      pass,
      input_runs,
      output_runs,
      largest_group: minimum_i64(input_runs, fan_in).to_int(),
    })
    input_runs = output_runs
    pass += 1
  }
  schedule
}

///|
/// Estimate a job from record count and original payload bytes. The model is
/// deterministic and saturates instead of wrapping Int64 counters.
pub fn estimate_job(
  input_records : Int64,
  input_payload_bytes : Int64,
  config : SortConfig,
) -> JobEstimate raise SortError {
  if input_records < 0L {
    raise InvalidConfig("input_records must not be negative")
  }
  if input_payload_bytes < 0L {
    raise InvalidConfig("input_payload_bytes must not be negative")
  }
  if input_records == 0L && input_payload_bytes != 0L {
    raise InvalidConfig("an empty input cannot have payload bytes")
  }
  let average_payload_bytes = if input_records == 0L {
    0L
  } else {
    ceil_div_i64(input_payload_bytes, input_records)
  }
  let estimated_record_bytes = match config.key_kind {
    TextKey =>
      saturating_add_i64(
        saturating_mul_i64(maximum_i64(average_payload_bytes, 1L), 2L),
        32L,
      )
    IntegerKey =>
      saturating_add_i64(maximum_i64(average_payload_bytes, 1L), 56L)
    DecimalKey =>
      saturating_add_i64(
        saturating_mul_i64(maximum_i64(average_payload_bytes, 1L), 2L),
        40L,
      )
  }
  let records_per_run = maximum_i64(
    1L,
    config.memory_budget_bytes.to_int64() / estimated_record_bytes,
  )
  let initial_runs = if input_records == 0L {
    0L
  } else {
    ceil_div_i64(input_records, records_per_run)
  }
  let schedule = build_merge_schedule(initial_runs, config.max_open_runs)
  let phase_count = schedule.length().to_int64() + 2L
  let io_multiplier = saturating_mul_i64(phase_count, 2L)
  let minimum_payload_io_bytes = saturating_mul_i64(
    input_payload_bytes, io_multiplier,
  )
  let peak_payload_generation_bytes = saturating_mul_i64(
    input_payload_bytes, 2L,
  )
  let saturated = minimum_payload_io_bytes == 9223372036854775807L ||
    peak_payload_generation_bytes == 9223372036854775807L ||
    estimated_record_bytes == 9223372036854775807L
  {
    input_records,
    input_payload_bytes,
    average_payload_bytes,
    records_per_run,
    initial_runs,
    merge_passes: schedule.length(),
    minimum_payload_io_bytes,
    peak_payload_generation_bytes,
    schedule,
    saturated,
  }
}

///|
/// Stable JSON form suitable for CLI wrappers and benchmark records.
pub fn job_estimate_json(estimate : JobEstimate) -> String {
  let schedule = StringBuilder()
  schedule.write_char('[')
  for index, pass in estimate.schedule {
    if index > 0 {
      schedule.write_char(',')
    }
    schedule.write_string(
      "{\"pass\":" +
      pass.pass.to_string() +
      ",\"inputRuns\":" +
      pass.input_runs.to_string() +
      ",\"outputRuns\":" +
      pass.output_runs.to_string() +
      ",\"largestGroup\":" +
      pass.largest_group.to_string() +
      "}",
    )
  }
  schedule.write_char(']')
  "{" +
  "\"schemaVersion\":1," +
  "\"inputRecords\":" +
  estimate.input_records.to_string() +
  ",\"inputPayloadBytes\":" +
  estimate.input_payload_bytes.to_string() +
  ",\"averagePayloadBytes\":" +
  estimate.average_payload_bytes.to_string() +
  ",\"recordsPerRun\":" +
  estimate.records_per_run.to_string() +
  ",\"initialRuns\":" +
  estimate.initial_runs.to_string() +
  ",\"mergePasses\":" +
  estimate.merge_passes.to_string() +
  ",\"minimumPayloadIoBytes\":" +
  estimate.minimum_payload_io_bytes.to_string() +
  ",\"peakPayloadGenerationBytes\":" +
  estimate.peak_payload_generation_bytes.to_string() +
  ",\"saturated\":" +
  estimate.saturated.to_string() +
  ",\"schedule\":" +
  schedule.to_string() +
  "}"
}

///|
fn ceil_div_i64(value : Int64, divisor : Int64) -> Int64 {
  if value == 0L {
    0L
  } else {
    1L + (value - 1L) / divisor
  }
}

///|
fn saturating_add_i64(left : Int64, right : Int64) -> Int64 {
  if left > 9223372036854775807L - right {
    9223372036854775807L
  } else {
    left + right
  }
}

///|
fn saturating_mul_i64(left : Int64, right : Int64) -> Int64 {
  if left == 0L || right == 0L {
    0L
  } else if left > 9223372036854775807L / right {
    9223372036854775807L
  } else {
    left * right
  }
}

///|
fn maximum_i64(left : Int64, right : Int64) -> Int64 {
  if left > right {
    left
  } else {
    right
  }
}

///|
fn minimum_i64(left : Int64, right : Int64) -> Int64 {
  if left < right {
    left
  } else {
    right
  }
}
