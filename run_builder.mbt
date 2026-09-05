///|
/// Incrementally creates bounded, internally ordered Runs.
pub struct RunBuilder {
  config : SortConfig
  mut records : Array[SortRecord]
  mut retained_bytes : Int
  mut next_position : Int64
}

///|
pub fn RunBuilder::new(
  config : SortConfig,
  start_position? : Int64 = 0L,
) -> RunBuilder raise SortError {
  if start_position < 0L {
    raise InvalidConfig("start_position must not be negative")
  }
  { config, records: [], retained_bytes: 0, next_position: start_position, }
}

///|
/// Accept one record and return a completed Run when the next record would
/// exceed the Resource Budget. The new record remains in the next Run.
pub fn RunBuilder::push(
  self : RunBuilder,
  payload : String,
  key_text : String,
) -> Array[SortRecord]? raise SortError {
  if payload.length() > self.config.max_record_bytes {
    raise RecordTooLarge(
      actual=payload.length(),
      limit=self.config.max_record_bytes,
    )
  }
  if self.next_position == 9223372036854775807L {
    raise SequenceExhausted
  }
  let record : SortRecord = {
    key: parse_key(key_text, self.config.key_kind),
    input_position: self.next_position,
    payload,
  }
  let required = estimated_record_bytes(record)
  if required > self.config.memory_budget_bytes {
    raise RecordTooLarge(actual=required, limit=self.config.memory_budget_bytes)
  }
  let completed = if self.records.length() > 0 &&
    required > self.config.memory_budget_bytes - self.retained_bytes {
    Some(self.take_run())
  } else {
    None
  }
  self.records.push(record)
  self.retained_bytes += required
  self.next_position += 1L
  completed
}

///|
/// Complete the final Run, or return `None` when no records remain.
pub fn RunBuilder::finish(self : RunBuilder) -> Array[SortRecord]? {
  if self.records.length() == 0 {
    None
  } else {
    Some(self.take_run())
  }
}

///|
pub fn RunBuilder::retained_bytes(self : RunBuilder) -> Int {
  self.retained_bytes
}

///|
pub fn RunBuilder::next_position(self : RunBuilder) -> Int64 {
  self.next_position
}

///|
fn RunBuilder::take_run(self : RunBuilder) -> Array[SortRecord] {
  let result = self.records
  self.records = []
  self.retained_bytes = 0
  result.sort_by((a, b) => compare_records(a, b, self.config.order))
  result
}
