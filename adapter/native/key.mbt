///|
fn decode_input_line(bytes : Bytes) -> String raise FileSortError {
  let content = match bytes.chop_suffix(b"\r") {
    Some(value) => value.to_owned()
    None => bytes
  }
  @utf8.decode(content) catch {
    _ => raise InvalidInput("input contains a line that is not valid UTF-8")
  }
}

///|
fn extract_key(
  line : String,
  selector : @sort.KeySelector,
) -> String raise FileSortError {
  match selector {
    @sort.WholeRecord => line
    @sort.DelimitedField(index~, delimiter~) => {
      let mut current = 0
      for field in line.split(delimiter) {
        if current == index {
          return field.to_owned()
        }
        current += 1
      }
      raise InvalidInput(
        "record does not contain delimited field " + index.to_string(),
      )
    }
    @sort.CsvField(index~, delimiter~) =>
      @sort.select_csv_field(
        line,
        index,
        dialect=@sort.CsvDialect::new(delimiter~),
      ) catch {
        @sort.CsvFieldMissing(index~, available~) =>
          raise InvalidInput(
            "CSV record has " +
            available.to_string() +
            " fields; requested field " +
            index.to_string(),
          )
        @sort.MalformedCsv(offset~, message~) =>
          raise InvalidInput(
            "invalid CSV record at byte " + offset.to_string() + ": " + message,
          )
        @sort.InvalidDialect(message) => raise InvalidInput(message)
      }
    @sort.JsonField(name) => {
      let value = @json.parse(line) catch {
        error =>
          raise InvalidInput("invalid JSONL record: " + error.to_string())
      }
      guard value is Object(fields) else {
        raise InvalidInput("JSONL record must be an object")
      }
      match fields.get(name) {
        Some(String(value)) => value
        Some(Number(number, repr~)) =>
          match repr {
            Some(text) => text
            None => number.to_string()
          }
        Some(True) => "true"
        Some(False) => "false"
        Some(Null) => raise InvalidInput("JSON key field is null: " + name)
        Some(_) => raise InvalidInput("JSON key field must be scalar: " + name)
        None => raise InvalidInput("JSON key field is missing: " + name)
      }
    }
  }
}
