///|
/// Durable phases in which a Sort Job may be recovered.
pub(all) enum JobPhase {
  RunsReady
  Merging
  Published
} derive(Debug, Eq)

///|
/// One committed Run referenced by a Job Manifest.
pub(all) struct RunDescriptor {
  path : String
  record_count : Int64
} derive(Debug, Eq)

///|
/// Portable recovery state. A Native adapter commits this document atomically
/// only after every Run referenced by it has been fully written.
pub(all) struct JobManifest {
  phase : JobPhase
  input_path : String
  output_path : String
  work_directory : String
  config : SortConfig
  selector : KeySelector
  input_records : Int64
  initial_run_count : Int
  merge_pass : Int
  runs : Array[RunDescriptor]
} derive(Debug, Eq)

///|
pub fn encode_manifest(manifest : JobManifest) -> String {
  let output = StringBuilder()
  output.write_string("{\"schemaVersion\":1")
  output.write_string(",\"phase\":" + json_text(phase_name(manifest.phase)))
  output.write_string(",\"inputPath\":" + json_text(manifest.input_path))
  output.write_string(",\"outputPath\":" + json_text(manifest.output_path))
  output.write_string(
    ",\"workDirectory\":" + json_text(manifest.work_directory),
  )
  output.write_string(
    ",\"order\":" + json_text(order_name(manifest.config.order)),
  )
  output.write_string(
    ",\"keyKind\":" + json_text(key_kind_name(manifest.config.key_kind)),
  )
  output.write_string(
    ",\"memoryBudgetBytes\":" + manifest.config.memory_budget_bytes.to_string(),
  )
  output.write_string(
    ",\"maxOpenRuns\":" + manifest.config.max_open_runs.to_string(),
  )
  output.write_string(
    ",\"maxRecordBytes\":" + manifest.config.max_record_bytes.to_string(),
  )
  output.write_string(",\"selector\":" + encode_selector(manifest.selector))
  output.write_string(",\"inputRecords\":" + manifest.input_records.to_string())
  output.write_string(
    ",\"initialRunCount\":" + manifest.initial_run_count.to_string(),
  )
  output.write_string(",\"mergePass\":" + manifest.merge_pass.to_string())
  output.write_string(",\"runs\":[")
  for index, run in manifest.runs {
    if index > 0 {
      output.write_char(',')
    }
    output.write_string(
      "{\"path\":" +
      json_text(run.path) +
      ",\"recordCount\":" +
      run.record_count.to_string() +
      "}",
    )
  }
  output.write_string("]}")
  output.to_string()
}

///|
pub fn decode_manifest(text : String) -> JobManifest raise SortError {
  let value = @json.parse(text) catch {
    error => raise InvalidManifest("invalid JSON: " + error.to_string())
  }
  guard value is Object(fields) else {
    raise InvalidManifest("manifest must be a JSON object")
  }
  if manifest_int(fields, "schemaVersion") != 1 {
    raise InvalidManifest("schemaVersion must be exactly 1")
  }
  let config = SortConfig::new(
    order=match manifest_string(fields, "order") {
      "ascending" => Ascending
      "descending" => Descending
      _ => raise InvalidManifest("unknown order")
    },
    key_kind=match manifest_string(fields, "keyKind") {
      "text" => TextKey
      "integer" => IntegerKey
      _ => raise InvalidManifest("unknown keyKind")
    },
    memory_budget_bytes=manifest_int(fields, "memoryBudgetBytes"),
    max_open_runs=manifest_int(fields, "maxOpenRuns"),
    max_record_bytes=manifest_int(fields, "maxRecordBytes"),
  ) catch {
    _ => raise InvalidManifest("manifest contains an invalid resource budget")
  }
  let selector = decode_selector(manifest_required(fields, "selector"))
  validate_selector(selector) catch {
    _ => raise InvalidManifest("manifest contains an invalid selector")
  }
  let runs_value = manifest_required(fields, "runs")
  guard runs_value is Array(items) else {
    raise InvalidManifest("runs must be an array")
  }
  let runs : Array[RunDescriptor] = []
  for item in items {
    guard item is Object(run_fields) else {
      raise InvalidManifest("run descriptor must be an object")
    }
    let record_count = manifest_int64(run_fields, "recordCount")
    if record_count < 0L {
      raise InvalidManifest("run recordCount must not be negative")
    }
    runs.push({ path: manifest_string(run_fields, "path"), record_count, })
  }
  let input_records = manifest_int64(fields, "inputRecords")
  let initial_run_count = manifest_int(fields, "initialRunCount")
  let merge_pass = manifest_int(fields, "mergePass")
  if input_records < 0L || initial_run_count < 0 || merge_pass < 0 {
    raise InvalidManifest("manifest counters must not be negative")
  }
  {
    phase: match manifest_string(fields, "phase") {
      "runs-ready" => RunsReady
      "merging" => Merging
      "published" => Published
      _ => raise InvalidManifest("unknown phase")
    },
    input_path: manifest_string(fields, "inputPath"),
    output_path: manifest_string(fields, "outputPath"),
    work_directory: manifest_string(fields, "workDirectory"),
    config,
    selector,
    input_records,
    initial_run_count,
    merge_pass,
    runs,
  }
}

///|
fn encode_selector(selector : KeySelector) -> String {
  match selector {
    WholeRecord => "{\"kind\":\"whole\"}"
    DelimitedField(index~, delimiter~) =>
      "{\"kind\":\"field\",\"index\":" +
      index.to_string() +
      ",\"delimiter\":" +
      json_text(delimiter) +
      "}"
    CsvField(index~, delimiter~) =>
      "{\"kind\":\"csv\",\"index\":" +
      index.to_string() +
      ",\"delimiter\":" +
      json_text(delimiter.to_string()) +
      "}"
    JsonField(name) => "{\"kind\":\"json\",\"name\":" + json_text(name) + "}"
  }
}

///|
fn decode_selector(value : Json) -> KeySelector raise SortError {
  guard value is Object(fields) else {
    raise InvalidManifest("selector must be an object")
  }
  match manifest_string(fields, "kind") {
    "whole" => WholeRecord
    "field" =>
      DelimitedField(
        index=manifest_int(fields, "index"),
        delimiter=manifest_string(fields, "delimiter"),
      )
    "csv" => {
      let chars = manifest_string(fields, "delimiter").to_array()
      if chars.length() != 1 {
        raise InvalidManifest("CSV delimiter must be one character")
      }
      CsvField(index=manifest_int(fields, "index"), delimiter=chars[0])
    }
    "json" => JsonField(manifest_string(fields, "name"))
    _ => raise InvalidManifest("unknown selector kind")
  }
}

///|
fn json_text(value : String) -> String {
  Json::string(value).stringify()
}

///|
fn phase_name(phase : JobPhase) -> String {
  match phase {
    RunsReady => "runs-ready"
    Merging => "merging"
    Published => "published"
  }
}

///|
fn order_name(order : SortOrder) -> String {
  match order {
    Ascending => "ascending"
    Descending => "descending"
  }
}

///|
fn key_kind_name(kind : KeyKind) -> String {
  match kind {
    TextKey => "text"
    IntegerKey => "integer"
  }
}

///|
fn manifest_required(
  fields : Map[String, Json],
  name : String,
) -> Json raise SortError {
  match fields.get(name) {
    Some(value) => value
    None => raise InvalidManifest("missing field: " + name)
  }
}

///|
fn manifest_string(
  fields : Map[String, Json],
  name : String,
) -> String raise SortError {
  match manifest_required(fields, name) {
    String(value) => value
    _ => raise InvalidManifest(name + " must be a string")
  }
}

///|
fn manifest_int(
  fields : Map[String, Json],
  name : String,
) -> Int raise SortError {
  let value = manifest_int64(fields, name)
  if value < -2147483648L || value > 2147483647L {
    raise InvalidManifest(name + " is outside Int range")
  }
  value.to_int()
}

///|
fn manifest_int64(
  fields : Map[String, Json],
  name : String,
) -> Int64 raise SortError {
  match manifest_required(fields, name) {
    Number(number, repr~) =>
      match repr {
        Some(text) =>
          @string.parse_int64(text) catch {
            _ => raise InvalidManifest(name + " must be an integer")
          }
        None => {
          if number != number.floor() ||
            number < -9007199254740991.0 ||
            number > 9007199254740991.0 {
            raise InvalidManifest(name + " must be an exact integer")
          }
          number.to_int64()
        }
      }
    _ => raise InvalidManifest(name + " must be an integer")
  }
}
