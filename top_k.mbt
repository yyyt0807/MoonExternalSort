///|
/// A completed stable Top-K selection and its resource accounting.
pub(all) struct TopKResult {
  records : Array[SortRecord]
  input_records : Int64
  discarded_records : Int64
  retained_bytes : Int
} derive(Debug, Eq)

///|
/// Streaming stable Top-K selection. The heap root is the worst retained
/// record, so an incoming better record can replace it in logarithmic time.
pub struct TopKSelector {
  config : SortConfig
  limit : Int
  heap : Array[SortRecord]
  mut retained_bytes : Int
  mut input_records : Int64
  mut discarded_records : Int64
  mut next_position : Int64
  mut finished : Bool
}

///|
pub fn TopKSelector::new(
  config : SortConfig,
  limit : Int,
  start_position? : Int64 = 0L,
) -> TopKSelector raise SortError {
  if limit < 0 {
    raise InvalidConfig("Top-K limit must not be negative")
  }
  if start_position < 0L {
    raise InvalidConfig("Top-K start_position must not be negative")
  }
  {
    config,
    limit,
    heap: [],
    retained_bytes: 0,
    input_records: 0L,
    discarded_records: 0L,
    next_position: start_position,
    finished: false,
  }
}

///|
/// Consider one record. Records equal on key remain ordered by their original
/// input positions because `compare_records` supplies the stable tie-breaker.
pub fn TopKSelector::push(
  self : TopKSelector,
  payload : String,
  key_text : String,
) -> Unit raise SortError {
  if self.finished {
    raise InvalidConfig("cannot push after TopKSelector.finish")
  }
  if payload.length() > self.config.max_record_bytes {
    raise RecordTooLarge(
      actual=payload.length(),
      limit=self.config.max_record_bytes,
    )
  }
  if self.next_position == 9223372036854775807L {
    raise SequenceExhausted
  }
  let record : SortRecord = {
    key: parse_key(key_text, self.config.key_kind),
    input_position: self.next_position,
    payload,
  }
  let required = estimated_record_bytes(record)
  if required > self.config.memory_budget_bytes {
    raise RecordTooLarge(actual=required, limit=self.config.memory_budget_bytes)
  }
  self.input_records += 1L
  self.next_position += 1L
  if self.limit == 0 {
    self.discarded_records += 1L
    return
  }
  if self.heap.length() < self.limit {
    ensure_selection_budget(
      self.retained_bytes + required,
      self.config.memory_budget_bytes,
    )
    self.heap.push(record)
    self.retained_bytes += required
    top_k_sift_up(self.heap, self.heap.length() - 1, self.config.order)
    return
  }
  if compare_records(record, self.heap[0], self.config.order) < 0 {
    let removed = estimated_record_bytes(self.heap[0])
    let replacement_bytes = self.retained_bytes - removed + required
    ensure_selection_budget(replacement_bytes, self.config.memory_budget_bytes)
    self.heap[0] = record
    self.retained_bytes = replacement_bytes
    top_k_sift_down(self.heap, 0, self.config.order)
  }
  self.discarded_records += 1L
}

///|
/// Return retained records in final output order. This method is single-use so
/// accounting cannot silently diverge after its array is handed to the caller.
pub fn TopKSelector::finish(self : TopKSelector) -> TopKResult raise SortError {
  if self.finished {
    raise InvalidConfig("TopKSelector.finish may be called only once")
  }
  self.finished = true
  self.heap.sort_by((left, right) => {
    compare_records(left, right, self.config.order)
  })
  {
    records: self.heap,
    input_records: self.input_records,
    discarded_records: self.discarded_records,
    retained_bytes: self.retained_bytes,
  }
}

///|
pub fn TopKSelector::retained_count(self : TopKSelector) -> Int {
  self.heap.length()
}

///|
pub fn TopKSelector::retained_bytes(self : TopKSelector) -> Int {
  self.retained_bytes
}

///|
pub fn TopKSelector::observed_count(self : TopKSelector) -> Int64 {
  self.input_records
}

///|
fn ensure_selection_budget(required : Int, limit : Int) -> Unit raise SortError {
  if required > limit {
    raise SelectionBudgetExceeded(required~, limit~)
  }
}

///|
/// Maintain a max-heap under the final output order: the worst selected record
/// stays at index zero.
fn top_k_sift_up(
  heap : Array[SortRecord],
  start : Int,
  order : SortOrder,
) -> Unit {
  let mut index = start
  while index > 0 {
    let parent = (index - 1) / 2
    if compare_records(heap[parent], heap[index], order) >= 0 {
      break
    }
    top_k_swap(heap, parent, index)
    index = parent
  }
}

///|
fn top_k_sift_down(
  heap : Array[SortRecord],
  start : Int,
  order : SortOrder,
) -> Unit {
  let mut index = start
  while true {
    let left = index * 2 + 1
    if left >= heap.length() {
      break
    }
    let right = left + 1
    let worse = if right < heap.length() &&
      compare_records(heap[right], heap[left], order) > 0 {
      right
    } else {
      left
    }
    if compare_records(heap[index], heap[worse], order) >= 0 {
      break
    }
    top_k_swap(heap, index, worse)
    index = worse
  }
}

///|
fn top_k_swap(heap : Array[SortRecord], left : Int, right : Int) -> Unit {
  let temporary = heap[left]
  heap[left] = heap[right]
  heap[right] = temporary
}
