///|
/// The first adjacent pair that violates the configured order.
pub(all) struct OrderViolation {
  previous_index : Int64
  current_index : Int64
  previous_key : SortValue
  current_key : SortValue
} derive(Debug, Eq)

///|
/// Summary produced by a streaming sortedness check.
pub(all) struct VerificationReport {
  records : Int64
  equal_adjacent_keys : Int64
  violation : OrderViolation?
} derive(Debug, Eq)

///|
/// Stateful constant-space verifier for an already ordered record stream.
pub struct SortednessVerifier {
  config : SortConfig
  mut previous : SortRecord?
  mut records : Int64
  mut equal_adjacent_keys : Int64
  mut violation : OrderViolation?
}

///|
pub fn SortednessVerifier::new(config : SortConfig) -> SortednessVerifier {
  {
    config,
    previous: None,
    records: 0L,
    equal_adjacent_keys: 0L,
    violation: None,
  }
}

///|
/// Verify one payload/key pair. Once a violation is found, later records are
/// counted but do not replace the first diagnostic.
pub fn SortednessVerifier::push(
  self : SortednessVerifier,
  payload : String,
  key_text : String,
) -> Unit raise SortError {
  if payload.length() > self.config.max_record_bytes {
    raise RecordTooLarge(
      actual=payload.length(),
      limit=self.config.max_record_bytes,
    )
  }
  if self.records == 9223372036854775807L {
    raise SequenceExhausted
  }
  let current : SortRecord = {
    key: parse_key(key_text, self.config.key_kind),
    input_position: self.records,
    payload,
  }
  self.push_record(current)
}

///|
/// Verify a record that already carries its original position. This overload
/// can also detect unstable ordering among equal keys.
pub fn SortednessVerifier::push_record(
  self : SortednessVerifier,
  current : SortRecord,
) -> Unit {
  match self.previous {
    Some(previous) => {
      let key_comparison = compare_sort_values(previous.key, current.key)
      if key_comparison == 0 {
        self.equal_adjacent_keys += 1L
      }
      let ordered = if key_comparison == 0 {
        previous.input_position <= current.input_position
      } else if self.config.order == Ascending {
        key_comparison < 0
      } else {
        key_comparison > 0
      }
      if !ordered && self.violation is None {
        self.violation = Some({
          previous_index: self.records - 1L,
          current_index: self.records,
          previous_key: previous.key,
          current_key: current.key,
        })
      }
    }
    None => ()
  }
  self.previous = Some(current)
  self.records += 1L
}

///|
pub fn SortednessVerifier::report(
  self : SortednessVerifier,
) -> VerificationReport {
  {
    records: self.records,
    equal_adjacent_keys: self.equal_adjacent_keys,
    violation: self.violation,
  }
}

///|
pub fn VerificationReport::is_sorted(self : VerificationReport) -> Bool {
  self.violation is None
}

///|
/// Compare keys without applying direction or stable position tie-breaking.
pub fn compare_sort_values(left : SortValue, right : SortValue) -> Int {
  match (left, right) {
    (TextValue(a), TextValue(b)) => a.compare(b)
    (IntegerValue(a), IntegerValue(b)) => a.compare(b)
    (DecimalValue(a), DecimalValue(b)) => compare_decimal_keys(a, b)
    (TextValue(_), IntegerValue(_)) => -1
    (TextValue(_), DecimalValue(_)) => -1
    (IntegerValue(_), TextValue(_)) => 1
    (IntegerValue(_), DecimalValue(_)) => -1
    (DecimalValue(_), TextValue(_)) => 1
    (DecimalValue(_), IntegerValue(_)) => 1
  }
}
