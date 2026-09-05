///|
/// Constant-space statistics over adjacent equal-key groups.
pub(all) struct GroupStatistics {
  records : Int64
  distinct_keys : Int64
  singleton_groups : Int64
  repeated_groups : Int64
  largest_group_records : Int64
  first_key : SortValue?
  last_key : SortValue?
  verification : VerificationReport
} derive(Debug, Eq)

///|
/// Streaming aggregation intended for sorted output. Statistics remain useful
/// when input is disordered, while `verification` preserves the first violation.
pub struct SortedGroupCounter {
  config : SortConfig
  verifier : SortednessVerifier
  mut previous_key : SortValue?
  mut first_key : SortValue?
  mut last_key : SortValue?
  mut records : Int64
  mut distinct_keys : Int64
  mut singleton_groups : Int64
  mut repeated_groups : Int64
  mut current_group_records : Int64
  mut largest_group_records : Int64
  mut next_position : Int64
  mut finished : Bool
}

///|
pub fn SortedGroupCounter::new(
  config : SortConfig,
  start_position? : Int64 = 0L,
) -> SortedGroupCounter raise SortError {
  if start_position < 0L {
    raise InvalidConfig("group counter start_position must not be negative")
  }
  {
    config,
    verifier: SortednessVerifier::new(config),
    previous_key: None,
    first_key: None,
    last_key: None,
    records: 0L,
    distinct_keys: 0L,
    singleton_groups: 0L,
    repeated_groups: 0L,
    current_group_records: 0L,
    largest_group_records: 0L,
    next_position: start_position,
    finished: false,
  }
}

///|
/// Parse and aggregate one external key.
pub fn SortedGroupCounter::push(
  self : SortedGroupCounter,
  payload : String,
  key_text : String,
) -> Unit raise SortError {
  if self.finished {
    raise InvalidConfig("cannot push after SortedGroupCounter.finish")
  }
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
  self.next_position += 1L
  self.push_record(record)
}

///|
/// Aggregate a record carrying an original position, enabling stability checks.
pub fn SortedGroupCounter::push_record(
  self : SortedGroupCounter,
  record : SortRecord,
) -> Unit raise SortError {
  if self.finished {
    raise InvalidConfig("cannot push after SortedGroupCounter.finish")
  }
  self.verifier.push_record(record)
  match self.previous_key {
    None => {
      self.first_key = Some(record.key)
      self.distinct_keys = 1L
      self.current_group_records = 1L
    }
    Some(previous) =>
      if compare_sort_values(previous, record.key) == 0 {
        self.current_group_records += 1L
      } else {
        self.close_group()
        self.distinct_keys += 1L
        self.current_group_records = 1L
      }
  }
  self.previous_key = Some(record.key)
  self.last_key = Some(record.key)
  self.records += 1L
  if self.current_group_records > self.largest_group_records {
    self.largest_group_records = self.current_group_records
  }
}

///|
/// Complete the last group and return immutable statistics.
pub fn SortedGroupCounter::finish(
  self : SortedGroupCounter,
) -> GroupStatistics raise SortError {
  if self.finished {
    raise InvalidConfig("SortedGroupCounter.finish may be called only once")
  }
  self.finished = true
  if self.current_group_records > 0L {
    self.close_group()
  }
  {
    records: self.records,
    distinct_keys: self.distinct_keys,
    singleton_groups: self.singleton_groups,
    repeated_groups: self.repeated_groups,
    largest_group_records: self.largest_group_records,
    first_key: self.first_key,
    last_key: self.last_key,
    verification: self.verifier.report(),
  }
}

///|
fn SortedGroupCounter::close_group(self : SortedGroupCounter) -> Unit {
  if self.current_group_records == 1L {
    self.singleton_groups += 1L
  } else if self.current_group_records > 1L {
    self.repeated_groups += 1L
  }
}

///|
pub fn GroupStatistics::is_sorted(self : GroupStatistics) -> Bool {
  self.verification.is_sorted()
}

///|
pub fn GroupStatistics::duplicate_records(self : GroupStatistics) -> Int64 {
  self.records - self.distinct_keys
}

///|
pub fn GroupStatistics::average_group_size(self : GroupStatistics) -> Double {
  if self.distinct_keys == 0L {
    0.0
  } else {
    self.records.to_double() / self.distinct_keys.to_double()
  }
}
