///|
/// Canonical arbitrary-precision decimal used only for ordering. `digits` has
/// no leading zero, `scale` counts fractional digits, and zero is never negative.
pub(all) struct DecimalKeyValue {
  negative : Bool
  digits : String
  scale : Int
} derive(Debug, Eq)

///|
/// Parse a plain decimal without converting through floating point. Exponents,
/// NaN and infinity are deliberately rejected to keep the accepted language
/// reproducible across MoonBit backends.
pub fn parse_decimal_key(text : String) -> DecimalKeyValue raise SortError {
  if text == "" {
    raise InvalidKey("decimal key must not be empty")
  }
  let chars = text.to_array()
  let mut offset = 0
  let mut negative = false
  if chars[0] == '-' || chars[0] == '+' {
    negative = chars[0] == '-'
    offset = 1
  }
  if offset == chars.length() {
    raise InvalidKey("decimal key must contain a digit")
  }
  let digits : Array[Char] = []
  let mut seen_point = false
  let mut fractional_digits = 0
  let mut digit_count = 0
  for index = offset; index < chars.length(); index = index + 1 {
    let char = chars[index]
    if char >= '0' && char <= '9' {
      digits.push(char)
      digit_count += 1
      if seen_point {
        fractional_digits += 1
      }
    } else if char == '.' && !seen_point {
      seen_point = true
    } else if char == '.' {
      raise InvalidKey(
        "decimal key contains more than one decimal point: " + text,
      )
    } else {
      raise InvalidKey(
        "invalid decimal character at offset " + index.to_string(),
      )
    }
  }
  if digit_count == 0 {
    raise InvalidKey("decimal key must contain a digit")
  }
  let mut first = 0
  while first < digits.length() && digits[first] == '0' {
    first += 1
  }
  if first == digits.length() {
    return { negative: false, digits: "0", scale: 0, }
  }
  let mut end = digits.length()
  let mut scale = fractional_digits
  while scale > 0 && end > first && digits[end - 1] == '0' {
    end -= 1
    scale -= 1
  }
  let output = StringBuilder()
  for index = first; index < end; index = index + 1 {
    output.write_char(digits[index])
  }
  { negative, digits: output.to_string(), scale, }
}

///|
/// Compare exact decimal values without allocation proportional to their
/// aligned scale and without integer overflow.
pub fn compare_decimal_keys(
  left : DecimalKeyValue,
  right : DecimalKeyValue,
) -> Int {
  if left.digits == "0" && right.digits == "0" {
    return 0
  }
  if left.negative != right.negative {
    return if left.negative { -1 } else { 1 }
  }
  let magnitude = compare_decimal_magnitude(left, right)
  if left.negative {
    -magnitude
  } else {
    magnitude
  }
}

///|
fn compare_decimal_magnitude(
  left : DecimalKeyValue,
  right : DecimalKeyValue,
) -> Int {
  let left_exponent = left.digits.length() - left.scale
  let right_exponent = right.digits.length() - right.scale
  if left_exponent < right_exponent {
    return -1
  }
  if left_exponent > right_exponent {
    return 1
  }
  let left_chars = left.digits.to_array()
  let right_chars = right.digits.to_array()
  let width = if left_chars.length() > right_chars.length() {
    left_chars.length()
  } else {
    right_chars.length()
  }
  for index = 0; index < width; index = index + 1 {
    let left_digit = if index < left_chars.length() {
      left_chars[index]
    } else {
      '0'
    }
    let right_digit = if index < right_chars.length() {
      right_chars[index]
    } else {
      '0'
    }
    if left_digit < right_digit {
      return -1
    }
    if left_digit > right_digit {
      return 1
    }
  }
  0
}

///|
/// Render a unique plain-decimal representation suitable for Run files.
pub fn DecimalKeyValue::to_canonical_string(self : DecimalKeyValue) -> String {
  if self.digits == "0" {
    return "0"
  }
  let output = StringBuilder()
  if self.negative {
    output.write_char('-')
  }
  let chars = self.digits.to_array()
  let integer_digits = chars.length() - self.scale
  if self.scale == 0 {
    output.write_string(self.digits)
  } else if integer_digits > 0 {
    for index = 0; index < chars.length(); index = index + 1 {
      if index == integer_digits {
        output.write_char('.')
      }
      output.write_char(chars[index])
    }
  } else {
    output.write_string("0.")
    for index = integer_digits; index < 0; index = index + 1 {
      output.write_char('0')
    }
    output.write_string(self.digits)
  }
  output.to_string()
}
