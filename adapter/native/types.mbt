///|
/// Native filesystem inputs for one new Sort Job.
#derive(Debug, Eq)
pub(all) struct FileSortOptions {
  input_path : String
  output_path : String
  work_directory : String
  config : @sort.SortConfig
  selector : @sort.KeySelector
  replace_output : Bool
}

///|
/// Native filesystem inputs for a constant-space sortedness check.
#derive(Debug, Eq)
pub(all) struct FileCheckOptions {
  input_path : String
  config : @sort.SortConfig
  selector : @sort.KeySelector
}

///|
/// Machine-readable result of checking one file without rewriting it.
#derive(Debug, Eq)
pub(all) struct FileCheckReport {
  input_path : String
  records : Int64
  equal_adjacent_keys : Int64
  sorted : Bool
  previous_index : Int64?
  current_index : Int64?
  previous_key : @sort.SortValue?
  current_key : @sort.SortValue?
}

///|
/// Stable machine-readable summary of a completed or already-published job.
#derive(Debug, Eq)
pub(all) struct SortReport {
  input_records : Int64
  initial_runs : Int32
  merge_passes : Int32
  output_path : String
  manifest_path : String
  recovered : Bool
}

///|
#derive(Debug, Eq)
pub(all) suberror FileSortError {
  WorkspaceExists(String)
  MissingArtifact(String)
  InvalidInput(String)
  OutputExists(String)
  CorruptRun(String)
}

///|
pub fn report_json(report : SortReport) -> String {
  "{" +
  "\"schemaVersion\":1," +
  "\"inputRecords\":" +
  report.input_records.to_string() +
  "," +
  "\"initialRuns\":" +
  report.initial_runs.to_string() +
  "," +
  "\"mergePasses\":" +
  report.merge_passes.to_string() +
  "," +
  "\"outputPath\":" +
  Json::string(report.output_path).stringify() +
  "," +
  "\"manifestPath\":" +
  Json::string(report.manifest_path).stringify() +
  "," +
  "\"recovered\":" +
  report.recovered.to_string() +
  "}"
}

///|
pub fn check_report_json(report : FileCheckReport) -> String {
  let violation_json = match
    (
      report.previous_index,
      report.current_index,
      report.previous_key,
      report.current_key,
    ) {
    (
      Some(previous_index),
      Some(current_index),
      Some(previous_key),
      Some(current_key),
    ) =>
      "{" +
      "\"previousIndex\":" +
      previous_index.to_string() +
      ",\"currentIndex\":" +
      current_index.to_string() +
      ",\"previousKey\":" +
      sort_value_json(previous_key) +
      ",\"currentKey\":" +
      sort_value_json(current_key) +
      "}"
    _ => "null"
  }
  "{" +
  "\"schemaVersion\":1," +
  "\"inputPath\":" +
  Json::string(report.input_path).stringify() +
  ",\"records\":" +
  report.records.to_string() +
  ",\"equalAdjacentKeys\":" +
  report.equal_adjacent_keys.to_string() +
  ",\"sorted\":" +
  report.sorted.to_string() +
  ",\"violation\":" +
  violation_json +
  "}"
}

///|
fn sort_value_json(value : @sort.SortValue) -> String {
  match value {
    @sort.TextValue(text) =>
      "{\"kind\":\"text\",\"value\":" + Json::string(text).stringify() + "}"
    @sort.IntegerValue(integer) =>
      "{\"kind\":\"integer\",\"value\":" + integer.to_string() + "}"
    @sort.DecimalValue(decimal) =>
      "{\"kind\":\"decimal\",\"value\":" +
      Json::string(decimal.to_canonical_string()).stringify() +
      "}"
  }
}

///|
pub extend FileCheckOptions with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend FileCheckOptions with Eq::{not_equal, equal}

///|
pub extend FileCheckReport with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend FileCheckReport with Eq::{not_equal, equal}

///|
pub extend FileSortError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend FileSortError with Eq::{not_equal, equal}

///|
pub extend FileSortOptions with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend FileSortOptions with Eq::{not_equal, equal}

///|
pub extend SortReport with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SortReport with Eq::{not_equal, equal}
