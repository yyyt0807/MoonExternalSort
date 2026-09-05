///|
/// Whether Sort Keys are compared from least to greatest or greatest to least.
pub(all) enum SortOrder {
  Ascending
  Descending
} derive(Debug, Eq)

///|
/// The supported v0.1 Sort Key domains.
pub(all) enum KeyKind {
  TextKey
  IntegerKey
} derive(Debug, Eq)

///|
/// A reproducible way to derive the Sort Key from one textual Input Record.
pub(all) enum KeySelector {
  WholeRecord
  DelimitedField(index~ : Int, delimiter~ : String)
  CsvField(index~ : Int, delimiter~ : Char)
  JsonField(String)
} derive(Debug, Eq)

///|
/// A parsed Sort Key. Keeping the value typed prevents lexical ordering from
/// silently being used for signed integers.
pub(all) enum SortValue {
  TextValue(String)
  IntegerValue(Int64)
} derive(Debug, Eq)

///|
/// One Input Record. `input_position` is always an ascending tie-breaker, even
/// for descending Sort Jobs, which makes the ordering stable.
pub(all) struct SortRecord {
  key : SortValue
  input_position : Int64
  payload : String
} derive(Debug, Eq)

///|
/// Hard algorithmic limits for a Sort Job.
pub(all) struct SortConfig {
  order : SortOrder
  key_kind : KeyKind
  memory_budget_bytes : Int
  max_open_runs : Int
  max_record_bytes : Int
} derive(Debug, Eq)

///|
/// Structured failures that callers can distinguish from host I/O failures.
pub(all) suberror SortError {
  InvalidConfig(String)
  InvalidKey(String)
  RecordTooLarge(actual~ : Int, limit~ : Int)
  SequenceExhausted
  MalformedRun(String)
  InvalidManifest(String)
} derive(Debug, Eq)

///|
/// Validate a Key Selector before reading input.
pub fn validate_selector(selector : KeySelector) -> Unit raise SortError {
  match selector {
    WholeRecord => ()
    DelimitedField(index~, delimiter~) => {
      if index < 0 {
        raise InvalidConfig("delimited field index must not be negative")
      }
      if delimiter == "" {
        raise InvalidConfig("delimiter must not be empty")
      }
    }
    CsvField(index~, delimiter~) => {
      if index < 0 {
        raise InvalidConfig("CSV field index must not be negative")
      }
      let _dialect = CsvDialect::new(delimiter~) catch {
        InvalidDialect(message) => raise InvalidConfig(message)
        _ => raise InvalidConfig("invalid CSV dialect")
      }
    }
    JsonField(name) =>
      if name == "" {
        raise InvalidConfig("JSON field name must not be empty")
      }
  }
}

///|
/// Construct and validate a Resource Budget.
pub fn SortConfig::new(
  order? : SortOrder = Ascending,
  key_kind? : KeyKind = TextKey,
  memory_budget_bytes? : Int = 8 * 1024 * 1024,
  max_open_runs? : Int = 32,
  max_record_bytes? : Int = 1024 * 1024,
) -> SortConfig raise SortError {
  if memory_budget_bytes < 256 {
    raise InvalidConfig("memory budget must be at least 256 bytes")
  }
  if max_open_runs < 2 {
    raise InvalidConfig("max_open_runs must be at least 2")
  }
  if max_record_bytes < 1 {
    raise InvalidConfig("max_record_bytes must be positive")
  }
  if max_record_bytes > memory_budget_bytes {
    raise InvalidConfig("max_record_bytes must not exceed memory budget")
  }
  { order, key_kind, memory_budget_bytes, max_open_runs, max_record_bytes, }
}

///|
/// Parse a typed Sort Key from its external text representation.
pub fn parse_key(text : String, kind : KeyKind) -> SortValue raise SortError {
  match kind {
    TextKey => TextValue(text)
    IntegerKey =>
      IntegerValue(
        @string.parse_int64(text) catch {
          _ => raise InvalidKey("not a signed 64-bit integer: " + text)
        },
      )
  }
}

///|
/// Compare two records according to Sort Key and stable Input Position.
pub fn compare_records(
  left : SortRecord,
  right : SortRecord,
  order : SortOrder,
) -> Int {
  let key_order = compare_sort_values(left.key, right.key)
  if key_order == 0 {
    left.input_position.compare(right.input_position)
  } else if order == Ascending {
    key_order
  } else {
    -key_order
  }
}

///|
/// Conservative retained-size estimate used to enforce the declared budget.
pub fn estimated_record_bytes(record : SortRecord) -> Int {
  let key_bytes = match record.key {
    TextValue(value) => value.length()
    IntegerValue(_) => 24
  }
  record.payload.length() + key_bytes + 32
}
