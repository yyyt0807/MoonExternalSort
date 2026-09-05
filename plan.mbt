///|
/// One bounded Merge Group expressed as half-open Run indexes.
pub(all) struct MergeGroup {
  start : Int
  end : Int
} derive(Debug, Eq)

///|
/// Plan one Merge Pass without opening files or allocating record buffers.
pub fn plan_merge_pass(
  run_count : Int,
  max_open_runs : Int,
) -> Array[MergeGroup] raise SortError {
  if run_count < 0 {
    raise InvalidConfig("run_count must not be negative")
  }
  if max_open_runs < 2 {
    raise InvalidConfig("max_open_runs must be at least 2")
  }
  let groups : Array[MergeGroup] = []
  let mut start = 0
  while start < run_count {
    let end = if start > run_count - max_open_runs {
      run_count
    } else {
      start + max_open_runs
    }
    groups.push({ start, end, })
    start = end
  }
  groups
}

///|
/// Number of Merge Passes required to reduce `run_count` Runs to one.
pub fn merge_pass_count(
  run_count : Int,
  max_open_runs : Int,
) -> Int raise SortError {
  if run_count < 0 {
    raise InvalidConfig("run_count must not be negative")
  }
  if max_open_runs < 2 {
    raise InvalidConfig("max_open_runs must be at least 2")
  }
  let mut count = run_count
  let mut passes = 0
  while count > 1 {
    count = (count + max_open_runs - 1) / max_open_runs
    passes += 1
  }
  passes
}
