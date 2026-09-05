///|
/// Bounded byte-oriented newline framing. It avoids an unbounded host
/// `read_until` buffer before `max_record_bytes` can be checked.
pub struct LineFramer {
  max_record_bytes : Int
  mut pending : Array[Byte]
  mut finished : Bool
}

///|
pub fn LineFramer::new(max_record_bytes : Int) -> LineFramer raise SortError {
  if max_record_bytes < 1 {
    raise InvalidConfig("max_record_bytes must be positive")
  }
  { max_record_bytes, pending: [], finished: false, }
}

///|
/// Consume an arbitrary byte chunk and return every complete line without its
/// LF delimiter. Empty lines are retained.
pub fn LineFramer::push(
  self : LineFramer,
  chunk : Bytes,
) -> Array[Bytes] raise SortError {
  if self.finished {
    raise InvalidConfig("cannot push input after LineFramer.finish")
  }
  let lines : Array[Bytes] = []
  for byte in chunk {
    if byte == b'\n' {
      lines.push(Bytes::from_array(self.pending))
      self.pending = []
    } else {
      if self.pending.length() >= self.max_record_bytes {
        raise RecordTooLarge(
          actual=self.pending.length() + 1,
          limit=self.max_record_bytes,
        )
      }
      self.pending.push(byte)
    }
  }
  lines
}

///|
/// Return the final unterminated line, if any. A trailing LF does not create an
/// additional record.
pub fn LineFramer::finish(self : LineFramer) -> Bytes? raise SortError {
  if self.finished {
    raise InvalidConfig("LineFramer.finish may be called only once")
  }
  self.finished = true
  if self.pending.length() == 0 {
    None
  } else {
    let line = Bytes::from_array(self.pending)
    self.pending = []
    Some(line)
  }
}

///|
pub fn LineFramer::pending_bytes(self : LineFramer) -> Int {
  self.pending.length()
}
