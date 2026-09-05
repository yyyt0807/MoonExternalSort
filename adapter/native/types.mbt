///|
/// Native filesystem inputs for one new Sort Job.
pub(all) struct FileSortOptions {
  input_path : String
  output_path : String
  work_directory : String
  config : @sort.SortConfig
  selector : @sort.KeySelector
  replace_output : Bool
} derive(Debug, Eq)

///|
/// Stable machine-readable summary of a completed or already-published job.
pub(all) struct SortReport {
  input_records : Int64
  initial_runs : Int
  merge_passes : Int
  output_path : String
  manifest_path : String
  recovered : Bool
} derive(Debug, Eq)

///|
pub(all) suberror FileSortError {
  WorkspaceExists(String)
  MissingArtifact(String)
  InvalidInput(String)
  OutputExists(String)
  CorruptRun(String)
} derive(Debug, Eq)

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
