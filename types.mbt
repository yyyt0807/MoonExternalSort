///|
/// Whether Sort Keys are compared from least to greatest or greatest to least.
#derive(Debug, Eq)
pub(all) enum SortOrder {
  Ascending
  Descending
}

///|
/// The supported v0.1 Sort Key domains.
#derive(Debug, Eq)
pub(all) enum KeyKind {
  TextKey
  IntegerKey
  DecimalKey
}

///|
/// A reproducible way to derive the Sort Key from one textual Input Record.
#derive(Debug, Eq)
pub(all) enum KeySelector {
  WholeRecord
  DelimitedField(index~ : Int32, delimiter~ : String)
  CsvField(index~ : Int32, delimiter~ : Char)
  JsonField(String)
}

///|
/// A parsed Sort Key. Keeping the value typed prevents lexical ordering from
/// silently being used for signed integers.
#derive(Debug, Eq)
pub(all) enum SortValue {
  TextValue(String)
  IntegerValue(Int64)
  DecimalValue(DecimalKeyValue)
}

///|
/// One Input Record. `input_position` is always an ascending tie-breaker, even
/// for descending Sort Jobs, which makes the ordering stable.
#derive(Debug, Eq)
pub(all) struct SortRecord {
  key : SortValue
  input_position : Int64
  payload : String
}

///|
/// Hard algorithmic limits for a Sort Job.
#derive(Debug, Eq)
pub(all) struct SortConfig {
  order : SortOrder
  key_kind : KeyKind
  memory_budget_bytes : Int32
  max_open_runs : Int32
  max_record_bytes : Int32
}

///|
/// Structured failures that callers can distinguish from host I/O failures.
#derive(Debug, Eq)
pub(all) suberror SortError {
  InvalidConfig(String)
  InvalidKey(String)
  RecordTooLarge(actual~ : Int32, limit~ : Int32)
  SelectionBudgetExceeded(required~ : Int32, limit~ : Int32)
  SequenceExhausted
  MalformedRun(String)
  InvalidManifest(String)
}

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
  order~ : SortOrder = Ascending,
  key_kind~ : KeyKind = TextKey,
  memory_budget_bytes~ : Int32 = 8 * 1024 * 1024,
  max_open_runs~ : Int32 = 32,
  max_record_bytes~ : Int32 = 1024 * 1024,
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
    DecimalKey => DecimalValue(parse_decimal_key(text))
  }
}

///|
/// Compare two records according to Sort Key and stable Input Position.
pub fn compare_records(
  left : SortRecord,
  right : SortRecord,
  order : SortOrder,
) -> Int32 {
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
pub fn estimated_record_bytes(record : SortRecord) -> Int32 {
  let key_bytes = match record.key {
    TextValue(value) => value.length()
    IntegerValue(_) => 24
    DecimalValue(value) => value.digits.length() + 8
  }
  record.payload.length() + key_bytes + 32
}

///|
pub extend KeyKind with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend KeyKind with Eq::{not_equal, equal}

///|
pub extend KeySelector with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend KeySelector with Eq::{not_equal, equal}

///|
pub extend SortConfig with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SortConfig with Eq::{not_equal, equal}

///|
pub extend SortError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SortError with Eq::{not_equal, equal}

///|
pub extend SortOrder with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SortOrder with Eq::{not_equal, equal}

///|
pub extend SortRecord with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SortRecord with Eq::{not_equal, equal}

///|
pub extend SortValue with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SortValue with Eq::{not_equal, equal}
