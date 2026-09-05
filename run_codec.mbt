///|
/// Encode one Run record as a self-contained JSON line. JSON escaping preserves
/// tabs, control characters, and arbitrary UTF-8 payloads without a custom
/// delimiter ambiguity.
pub fn encode_run_record(record : SortRecord) -> String {
  let (kind, key) = match record.key {
    TextValue(value) => ("text", Json::string(value).stringify())
    IntegerValue(value) => ("integer", value.to_string())
  }
  "{" +
  "\"kind\":" +
  Json::string(kind).stringify() +
  "," +
  "\"key\":" +
  key +
  "," +
  "\"position\":" +
  record.input_position.to_string() +
  "," +
  "\"payload\":" +
  Json::string(record.payload).stringify() +
  "}"
}

///|
/// Decode and validate one Run record.
pub fn decode_run_record(line : String) -> SortRecord raise SortError {
  let value = @json.parse(line) catch {
    error => raise MalformedRun("invalid JSON: " + error.to_string())
  }
  guard value is Object(fields) else {
    raise MalformedRun("record must be a JSON object")
  }
  let kind = required_string(fields, "kind")
  let key = match kind {
    "text" => TextValue(required_string(fields, "key"))
    "integer" => IntegerValue(required_int64(fields, "key"))
    _ => raise MalformedRun("unknown key kind: " + kind)
  }
  let input_position = required_int64(fields, "position")
  if input_position < 0L {
    raise MalformedRun("position must not be negative")
  }
  { key, input_position, payload: required_string(fields, "payload"), }
}

///|
fn required_string(
  fields : Map[String, Json],
  name : String,
) -> String raise SortError {
  match fields.get(name) {
    Some(String(value)) => value
    Some(_) => raise MalformedRun(name + " must be a string")
    None => raise MalformedRun("missing field: " + name)
  }
}

///|
fn required_int64(
  fields : Map[String, Json],
  name : String,
) -> Int64 raise SortError {
  match fields.get(name) {
    Some(Number(number, repr~)) =>
      match repr {
        Some(text) =>
          @string.parse_int64(text) catch {
            _ => raise MalformedRun(name + " must be a signed 64-bit integer")
          }
        None => {
          if number != number.floor() ||
            number < -9007199254740991.0 ||
            number > 9007199254740991.0 {
            raise MalformedRun(name + " must be an exact integer")
          }
          number.to_int64()
        }
      }
    Some(_) => raise MalformedRun(name + " must be an integer")
    None => raise MalformedRun("missing field: " + name)
  }
}
