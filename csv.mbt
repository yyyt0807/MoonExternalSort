///|
/// CSV parsing and rendering failures. This codec operates on one logical
/// record, so physical line framing remains the caller's responsibility.
pub(all) suberror CsvError {
  InvalidDialect(String)
  MalformedCsv(offset~ : Int, message~ : String)
  CsvFieldMissing(index~ : Int, available~ : Int)
} derive(Debug, Eq)

///|
/// Syntax characters for the single-record CSV codec.
pub(all) struct CsvDialect {
  delimiter : Char
  quote : Char
} derive(Debug, Eq)

///|
/// Construct a validated dialect.
pub fn CsvDialect::new(
  delimiter? : Char = ',',
  quote? : Char = '"',
) -> CsvDialect raise CsvError {
  if delimiter == quote {
    raise InvalidDialect("delimiter and quote must be different")
  }
  if delimiter == '\r' || delimiter == '\n' || quote == '\r' || quote == '\n' {
    raise InvalidDialect("delimiter and quote must not be a line break")
  }
  { delimiter, quote, }
}

///|
/// Parse one CSV record. Quotes are allowed only at the beginning of a field,
/// and a doubled quote inside a quoted field decodes to one quote.
pub fn parse_csv_record(
  record : String,
  dialect? : CsvDialect = { delimiter: ',', quote: '"', },
) -> Array[String] raise CsvError {
  let fields : Array[String] = []
  let mut field = StringBuilder()
  let mut state = 0
  let mut offset = 0
  for char in record {
    if char == '\r' || char == '\n' {
      raise MalformedCsv(offset~, message="line break inside one CSV record")
    }
    match state {
      0 =>
        if char == dialect.delimiter {
          fields.push("")
        } else if char == dialect.quote {
          state = 2
        } else {
          field.write_char(char)
          state = 1
        }
      1 =>
        if char == dialect.delimiter {
          fields.push(field.to_string())
          field = StringBuilder()
          state = 0
        } else if char == dialect.quote {
          raise MalformedCsv(offset~, message="quote inside an unquoted field")
        } else {
          field.write_char(char)
        }
      2 =>
        if char == dialect.quote {
          state = 3
        } else {
          field.write_char(char)
        }
      3 =>
        if char == dialect.quote {
          field.write_char(char)
          state = 2
        } else if char == dialect.delimiter {
          fields.push(field.to_string())
          field = StringBuilder()
          state = 0
        } else {
          raise MalformedCsv(
            offset~,
            message="unexpected character after closing quote",
          )
        }
      _ => abort("unreachable CSV parser state")
    }
    offset += char.to_string().length()
  }
  if state == 2 {
    raise MalformedCsv(offset~, message="unterminated quoted field")
  }
  fields.push(field.to_string())
  fields
}

///|
/// Select one decoded field and report the available field count on failure.
pub fn select_csv_field(
  record : String,
  index : Int,
  dialect? : CsvDialect = { delimiter: ',', quote: '"', },
) -> String raise CsvError {
  if index < 0 {
    raise CsvFieldMissing(index~, available=0)
  }
  let fields = parse_csv_record(record, dialect~)
  if index >= fields.length() {
    raise CsvFieldMissing(index~, available=fields.length())
  }
  fields[index]
}

///|
/// Render one field with the minimum quoting necessary for the dialect.
pub fn encode_csv_field(
  value : String,
  dialect? : CsvDialect = { delimiter: ',', quote: '"', },
) -> String {
  let mut quoted = value == ""
  for char in value {
    if char == dialect.delimiter ||
      char == dialect.quote ||
      char == '\r' ||
      char == '\n' {
      quoted = true
    }
  }
  if !quoted {
    return value
  }
  let output = StringBuilder()
  output.write_char(dialect.quote)
  for char in value {
    if char == dialect.quote {
      output.write_char(dialect.quote)
    }
    output.write_char(char)
  }
  output.write_char(dialect.quote)
  output.to_string()
}

///|
/// Encode a complete record using the supplied dialect.
pub fn encode_csv_record(
  fields : Array[String],
  dialect? : CsvDialect = { delimiter: ',', quote: '"', },
) -> String {
  let output = StringBuilder()
  for index, field in fields {
    if index > 0 {
      output.write_char(dialect.delimiter)
    }
    output.write_string(encode_csv_field(field, dialect~))
  }
  output.to_string()
}
