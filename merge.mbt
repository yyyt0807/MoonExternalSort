///|
priv struct HeapEntry {
  record : SortRecord
  run_index : Int
}

///|
/// Reference k-way merge over materialized Runs. Native storage adapters use
/// the same ordering contract while loading only one head per open Run.
pub fn merge_sorted_runs(
  runs : Array[Array[SortRecord]],
  order : SortOrder,
) -> Array[SortRecord] {
  let positions = Array::make(runs.length(), 0)
  let heap : Array[HeapEntry] = []
  let output : Array[SortRecord] = []
  for run_index, run in runs {
    if run.length() > 0 {
      heap_push(heap, { record: run[0], run_index, }, order)
      positions[run_index] = 1
    }
  }
  while heap.length() > 0 {
    let entry = heap_pop(heap, order)
    output.push(entry.record)
    let position = positions[entry.run_index]
    let run = runs[entry.run_index]
    if position < run.length() {
      heap_push(
        heap,
        { record: run[position], run_index: entry.run_index, },
        order,
      )
      positions[entry.run_index] = position + 1
    }
  }
  output
}

///|
fn heap_push(
  heap : Array[HeapEntry],
  entry : HeapEntry,
  order : SortOrder,
) -> Unit {
  heap.push(entry)
  let mut index = heap.length() - 1
  while index > 0 {
    let parent = (index - 1) / 2
    if compare_records(heap[parent].record, heap[index].record, order) <= 0 {
      break
    }
    let temporary = heap[parent]
    heap[parent] = heap[index]
    heap[index] = temporary
    index = parent
  }
}

///|
fn heap_pop(heap : Array[HeapEntry], order : SortOrder) -> HeapEntry {
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
      compare_records(heap[right].record, heap[left].record, order) < 0 {
      right
    } else {
      left
    }
    if compare_records(heap[index].record, heap[smallest].record, order) <= 0 {
      break
    }
    let temporary = heap[index]
    heap[index] = heap[smallest]
    heap[smallest] = temporary
    index = smallest
  }
  result
}
