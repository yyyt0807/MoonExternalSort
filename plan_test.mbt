///|
test "merge pass obeys fan-in and covers every run exactly once" {
  assert_eq(plan_merge_pass(10, 3), [
    { start: 0, end: 3, },
    { start: 3, end: 6, },
    { start: 6, end: 9, },
    { start: 9, end: 10, },
  ])
}

///|
test "merge pass count handles empty, singleton, and multi-pass jobs" {
  assert_eq(merge_pass_count(0, 4), 0)
  assert_eq(merge_pass_count(1, 4), 0)
  assert_eq(merge_pass_count(4, 4), 1)
  assert_eq(merge_pass_count(17, 4), 3)
}
