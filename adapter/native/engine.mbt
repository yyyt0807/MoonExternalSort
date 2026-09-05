///|
priv struct MergeHead {
  record : @sort.SortRecord
  reader_index : Int
}

///|
/// Start a new filesystem Sort Job and publish its output atomically.
pub async fn sort_file(options : FileSortOptions) -> SortReport {
  @sort.validate_selector(options.selector)
  if !@fs.exists(options.input_path) {
    raise MissingArtifact("input does not exist: " + options.input_path)
  }
  if @fs.exists(options.work_directory) {
    raise WorkspaceExists(
      "work directory already exists; use resume or choose another path: " +
      options.work_directory,
    )
  }
  if @fs.exists(options.output_path) && !options.replace_output {
    raise OutputExists("output already exists: " + options.output_path)
  }
  @fs.mkdir(options.work_directory, recursive=true)
  let input = @fs.open(options.input_path, mode=ReadOnly)
  defer input.close()
  let framer = @sort.LineFramer::new(options.config.max_record_bytes)
  let builder = @sort.RunBuilder::new(options.config)
  let runs : Array[@sort.RunDescriptor] = []
  let mut run_index = 0
  while input.read_some(max_len=8192) is Some(chunk) {
    for raw_line in framer.push(chunk) {
      let line = decode_input_line(raw_line)
      let key = extract_key(line, options.selector)
      match builder.push(line, key) {
        Some(records) => {
          let path = run_path(options.work_directory, 0, run_index)
          write_materialized_run(path, records)
          runs.push({ path, record_count: records.length().to_int64(), })
          run_index += 1
        }
        None => ()
      }
    }
  }
  match framer.finish() {
    Some(raw_line) => {
      let line = decode_input_line(raw_line)
      let key = extract_key(line, options.selector)
      match builder.push(line, key) {
        Some(records) => {
          let path = run_path(options.work_directory, 0, run_index)
          write_materialized_run(path, records)
          runs.push({ path, record_count: records.length().to_int64(), })
          run_index += 1
        }
        None => ()
      }
    }
    None => ()
  }
  match builder.finish() {
    Some(records) => {
      let path = run_path(options.work_directory, 0, run_index)
      write_materialized_run(path, records)
      runs.push({ path, record_count: records.length().to_int64(), })
    }
    None => ()
  }
  let manifest : @sort.JobManifest = {
    phase: @sort.RunsReady,
    input_path: options.input_path,
    output_path: options.output_path,
    work_directory: options.work_directory,
    config: options.config,
    selector: options.selector,
    input_records: builder.next_position(),
    initial_run_count: runs.length(),
    merge_pass: 0,
    runs,
  }
  let path = manifest_path(options.work_directory)
  commit_manifest(path, manifest)
  continue_job(path, options.replace_output, false)
}

///|
/// Continue only from the last atomically committed Job Manifest. Files from an
/// interrupted, uncommitted Merge Pass are overwritten and never trusted.
pub async fn resume_file(
  manifest_path : String,
  replace_output? : Bool = false,
) -> SortReport {
  if !@fs.exists(manifest_path) {
    raise MissingArtifact("manifest does not exist: " + manifest_path)
  }
  continue_job(manifest_path, replace_output, true)
}

///|
async fn continue_job(
  manifest_path_value : String,
  replace_output : Bool,
  recovered : Bool,
) -> SortReport {
  let text = @fs.read_file(manifest_path_value).text()
  let mut manifest = @sort.decode_manifest(text)
  let initial_runs = manifest.initial_run_count
  if manifest.phase == @sort.Published {
    if !@fs.exists(manifest.output_path) {
      raise MissingArtifact(
        "manifest is published but output is missing: " + manifest.output_path,
      )
    }
    return {
      input_records: manifest.input_records,
      initial_runs,
      merge_passes: manifest.merge_pass,
      output_path: manifest.output_path,
      manifest_path: manifest_path_value,
      recovered,
    }
  }
  for run in manifest.runs {
    if !@fs.exists(run.path) {
      raise MissingArtifact("committed run is missing: " + run.path)
    }
  }
  while manifest.runs.length() > 1 {
    let groups = @sort.plan_merge_pass(
      manifest.runs.length(),
      manifest.config.max_open_runs,
    )
    let next_runs : Array[@sort.RunDescriptor] = []
    let next_pass = manifest.merge_pass + 1
    for group_index, group in groups {
      if group.end - group.start == 1 {
        next_runs.push(manifest.runs[group.start])
        continue
      }
      let inputs : Array[@sort.RunDescriptor] = []
      let mut index = group.start
      while index < group.end {
        inputs.push(manifest.runs[index])
        index += 1
      }
      let path = run_path(manifest.work_directory, next_pass, group_index)
      let count = merge_run_files(path, inputs, manifest.config.order)
      next_runs.push({ path, record_count: count, })
    }
    let previous_runs = manifest.runs
    manifest = {
      ..manifest,
      phase: @sort.Merging,
      merge_pass: next_pass,
      runs: next_runs,
    }
    commit_manifest(manifest_path_value, manifest)
    for run in previous_runs {
      if !contains_run(manifest.runs, run.path) && @fs.exists(run.path) {
        @fs.remove(run.path)
      }
    }
  }
  publish_output(manifest, replace_output)
  manifest = { ..manifest, phase: @sort.Published, }
  commit_manifest(manifest_path_value, manifest)
  {
    input_records: manifest.input_records,
    initial_runs,
    merge_passes: manifest.merge_pass,
    output_path: manifest.output_path,
    manifest_path: manifest_path_value,
    recovered,
  }
}

///|
async fn write_materialized_run(
  path : String,
  records : Array[@sort.SortRecord],
) -> Unit {
  let temporary = path + ".tmp"
  if @fs.exists(temporary) {
    @fs.remove(temporary)
  }
  write_materialized_run_contents(temporary, records)
  @fs.rename(temporary, path, replace=true)
}

///|
async fn write_materialized_run_contents(
  temporary : String,
  records : Array[@sort.SortRecord],
) -> Unit {
  let file = @fs.open(temporary, mode=WriteOnly, create_mode=CreateOrTruncate)
  defer file.close()
  let writer = @io.BufferedWriter::new(file, size=64 * 1024)
  for record in records {
    writer.write(@sort.encode_run_record(record) + "\n")
  }
  writer.flush()
  file.sync(only_data=true)
}

///|
async fn merge_run_files(
  output_path : String,
  inputs : Array[@sort.RunDescriptor],
  order : @sort.SortOrder,
) -> Int64 {
  let temporary = output_path + ".tmp"
  if @fs.exists(temporary) {
    @fs.remove(temporary)
  }
  let written = merge_run_contents(temporary, inputs, order)
  @fs.rename(temporary, output_path, replace=true)
  written
}

///|
async fn merge_run_contents(
  temporary : String,
  inputs : Array[@sort.RunDescriptor],
  order : @sort.SortOrder,
) -> Int64 {
  let readers : Array[@fs.File] = []
  for input in inputs {
    readers.push(@fs.open(input.path, mode=ReadOnly))
  }
  defer (for reader in readers {
    reader.close()
  })
  let output = @fs.open(temporary, mode=WriteOnly, create_mode=CreateOrTruncate)
  defer output.close()
  let writer = @io.BufferedWriter::new(output, size=64 * 1024)
  let heap : Array[MergeHead] = []
  for reader_index, reader in readers {
    match read_run_head(reader) {
      Some(record) => heap_push(heap, { record, reader_index, }, order)
      None => ()
    }
  }
  let mut written = 0L
  while heap.length() > 0 {
    let head = heap_pop(heap, order)
    writer.write(@sort.encode_run_record(head.record) + "\n")
    written += 1L
    match read_run_head(readers[head.reader_index]) {
      Some(record) =>
        heap_push(heap, { record, reader_index: head.reader_index, }, order)
      None => ()
    }
  }
  let expected = inputs.fold(init=0L, (total, run) => total + run.record_count)
  if written != expected {
    raise CorruptRun(
      "merged record count " +
      written.to_string() +
      " does not match manifest count " +
      expected.to_string(),
    )
  }
  writer.flush()
  output.sync(only_data=true)
  written
}

///|
async fn read_run_head(reader : @fs.File) -> @sort.SortRecord? {
  match reader.read_until("\n") {
    Some(line) if line == "" => raise CorruptRun("run contains an empty line")
    Some(line) =>
      Some(
        @sort.decode_run_record(line) catch {
          _ => raise CorruptRun("invalid committed run record")
        },
      )
    None => None
  }
}

///|
async fn publish_output(
  manifest : @sort.JobManifest,
  replace_output : Bool,
) -> Unit {
  if @fs.exists(manifest.output_path) && !replace_output {
    raise OutputExists("output already exists: " + manifest.output_path)
  }
  let temporary = manifest.output_path + ".moon-external-sort.tmp"
  if @fs.exists(temporary) {
    @fs.remove(temporary)
  }
  publish_output_contents(temporary, manifest)
  @fs.rename(temporary, manifest.output_path, replace=replace_output)
}

///|
async fn publish_output_contents(
  temporary : String,
  manifest : @sort.JobManifest,
) -> Unit {
  let output = @fs.open(temporary, mode=WriteOnly, create_mode=CreateOrTruncate)
  defer output.close()
  let writer = @io.BufferedWriter::new(output, size=64 * 1024)
  if manifest.runs.length() == 1 {
    let input = @fs.open(manifest.runs[0].path, mode=ReadOnly)
    defer input.close()
    let mut records = 0L
    while read_run_head(input) is Some(record) {
      writer.write(record.payload + "\n")
      records += 1L
    }
    if records != manifest.input_records {
      raise CorruptRun("final Run record count does not match Job Manifest")
    }
  } else if manifest.input_records != 0L {
    raise CorruptRun("non-empty job has no final Run")
  }
  writer.flush()
  output.sync(only_data=true)
}

///|
async fn commit_manifest(path : String, manifest : @sort.JobManifest) -> Unit {
  let temporary = path + ".tmp"
  @fs.write_file(
    temporary,
    @sort.encode_manifest(manifest) + "\n",
    create_mode=CreateOrTruncate,
    sync=Full,
  )
  @fs.rename(temporary, path, replace=true)
}

///|
fn manifest_path(work_directory : String) -> String {
  work_directory + "/manifest.json"
}

///|
fn run_path(work_directory : String, pass : Int, group : Int) -> String {
  work_directory +
  "/pass-" +
  pass.to_string() +
  "-run-" +
  group.to_string() +
  ".run"
}

///|
fn contains_run(runs : Array[@sort.RunDescriptor], path : String) -> Bool {
  for run in runs {
    if run.path == path {
      return true
    }
  }
  false
}

///|
fn heap_push(
  heap : Array[MergeHead],
  head : MergeHead,
  order : @sort.SortOrder,
) -> Unit {
  heap.push(head)
  let mut index = heap.length() - 1
  while index > 0 {
    let parent = (index - 1) / 2
    if @sort.compare_records(heap[parent].record, heap[index].record, order) <=
      0 {
      break
    }
    let temporary = heap[parent]
    heap[parent] = heap[index]
    heap[index] = temporary
    index = parent
  }
}

///|
fn heap_pop(heap : Array[MergeHead], order : @sort.SortOrder) -> MergeHead {
  let result = heap[0]
  let last_index = heap.length() - 1
  if last_index == 0 {
    ignore(heap.pop())
    return result
  }
  heap[0] = heap[last_index]
  ignore(heap.pop())
  let mut index = 0
  while true {
    let left = index * 2 + 1
    if left >= heap.length() {
      break
    }
    let right = left + 1
    let smallest = if right < heap.length() &&
      @sort.compare_records(heap[right].record, heap[left].record, order) < 0 {
      right
    } else {
      left
    }
    if @sort.compare_records(heap[index].record, heap[smallest].record, order) <=
      0 {
      break
    }
    let temporary = heap[index]
    heap[index] = heap[smallest]
    heap[smallest] = temporary
    index = smallest
  }
  result
}
