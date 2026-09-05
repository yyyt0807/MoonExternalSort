///|
/// Check whether a file already follows the configured ordering. Input is read
/// through the same bounded line framer and key selectors used by sorting.
pub async fn check_file(options : FileCheckOptions) -> FileCheckReport {
  @sort.validate_selector(options.selector)
  if !@fs.exists(options.input_path) {
    raise MissingArtifact("input does not exist: " + options.input_path)
  }
  let input = @fs.open(options.input_path, mode=ReadOnly)
  defer input.close()
  let framer = @sort.LineFramer::new(options.config.max_record_bytes)
  let verifier = @sort.SortednessVerifier::new(options.config)
  while input.read_some(max_len=8192) is Some(chunk) {
    for raw_line in framer.push(chunk) {
      check_one_line(verifier, raw_line, options.selector)
    }
  }
  match framer.finish() {
    Some(raw_line) => check_one_line(verifier, raw_line, options.selector)
    None => ()
  }
  let report = verifier.report()
  match report.violation {
    Some(violation) =>
      {
        input_path: options.input_path,
        records: report.records,
        equal_adjacent_keys: report.equal_adjacent_keys,
        sorted: false,
        previous_index: Some(violation.previous_index),
        current_index: Some(violation.current_index),
        previous_key: Some(violation.previous_key),
        current_key: Some(violation.current_key),
      }
    None =>
      {
        input_path: options.input_path,
        records: report.records,
        equal_adjacent_keys: report.equal_adjacent_keys,
        sorted: true,
        previous_index: None,
        current_index: None,
        previous_key: None,
        current_key: None,
      }
  }
}

///|
fn check_one_line(
  verifier : @sort.SortednessVerifier,
  raw_line : Bytes,
  selector : @sort.KeySelector,
) -> Unit raise {
  let line = decode_input_line(raw_line)
  let key = extract_key(line, selector)
  verifier.push(line, key)
}
