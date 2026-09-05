///|
fn main raise {
  let config = @sort.SortConfig::new(
    memory_budget_bytes=512,
    max_open_runs=2,
    max_record_bytes=128,
  )
  let builder = @sort.RunBuilder::new(config)
  let runs : Array[Array[@sort.SortRecord]] = []
  for
    pair in [
      ("c", "charlie"),
      ("a", "alpha-first"),
      ("b", "bravo"),
      ("a", "alpha-second"),
    ] {
    let (key, payload) = pair
    match builder.push(payload, key) {
      Some(run) => runs.push(run)
      None => ()
    }
  }
  match builder.finish() {
    Some(run) => runs.push(run)
    None => ()
  }
  for record in @sort.merge_sorted_runs(runs, config.order) {
    println(record.payload)
  }
}
