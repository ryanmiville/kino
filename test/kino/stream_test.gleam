import gleam/int
import gleam/list
import gleeunit/should
import kino/stream.{Next}

pub fn single_test() {
  stream.single(1)
  |> stream.to_list
  |> should.equal(Ok([1]))
}

pub fn from_list_test() {
  stream.from_list([1, 2, 3])
  |> stream.to_list
  |> should.equal(Ok([1, 2, 3]))
}

pub fn map_test() {
  stream.from_list([1, 2, 3])
  |> stream.map(int.multiply(_, 2))
  |> stream.to_list
  |> should.equal(Ok([2, 4, 6]))
}

pub fn take_test() {
  let counter = stream.unfold(0, fn(acc) { stream.Next(acc, acc + 1) })
  counter
  |> stream.take(3)
  |> stream.to_list
  |> should.equal(Ok([0, 1, 2]))
}

pub fn filter_test() {
  stream.from_list([1, 2, 3])
  |> stream.filter(int.is_even)
  |> stream.to_list
  |> should.equal(Ok([2]))
}

pub fn repeat_test() {
  stream.repeat(1)
  |> stream.take(4)
  |> stream.to_list
  |> should.equal(Ok([1, 1, 1, 1]))
}

pub fn append_test() {
  stream.from_list([1, 2, 3])
  |> stream.append(stream.from_list([4, 5, 6]))
  |> stream.to_list
  |> should.equal(Ok([1, 2, 3, 4, 5, 6]))

  stream.from_list([1, 2, 3])
  |> stream.map(int.multiply(_, 2))
  |> stream.append(
    stream.from_list([4, 5, 6]) |> stream.map(int.multiply(_, 2)),
  )
  |> stream.to_list
  |> should.equal(Ok([2, 4, 6, 8, 10, 12]))

  stream.from_list([1, 2, 3])
  |> stream.async
  |> stream.map(int.multiply(_, 2))
  |> stream.append(
    stream.from_list([4, 5, 6]) |> stream.map(int.multiply(_, 2)),
  )
  |> stream.to_list
  |> should.equal(Ok([2, 4, 6, 8, 10, 12]))

  stream.from_list([1, 2, 3])
  |> stream.map(int.multiply(_, 2))
  |> stream.append(
    stream.from_list([4, 5, 6])
    |> stream.async
    |> stream.map(int.multiply(_, 2)),
  )
  |> stream.to_list
  |> should.equal(Ok([2, 4, 6, 8, 10, 12]))

  stream.from_list([1, 2, 3])
  |> stream.async
  |> stream.map(int.multiply(_, 2))
  |> stream.append(
    stream.from_list([4, 5, 6])
    |> stream.async
    |> stream.map(int.multiply(_, 2)),
  )
  |> stream.to_list
  |> should.equal(Ok([2, 4, 6, 8, 10, 12]))
}

pub fn range_test() {
  let testcase = fn(a, b, expected) {
    stream.range(a, b)
    |> stream.to_list
    |> should.equal(Ok(expected))
  }

  testcase(0, 0, [0])
  testcase(1, 1, [1])
  testcase(-1, -1, [-1])
  testcase(0, 1, [0, 1])
  testcase(0, 5, [0, 1, 2, 3, 4, 5])
  testcase(1, -5, [1, 0, -1, -2, -3, -4, -5])
}

pub fn iterate_test() {
  fn(x) { x * 3 }
  |> stream.iterate(from: 1)
  |> stream.take(5)
  |> stream.to_list
  |> should.equal(Ok([1, 3, 9, 27, 81]))
}

pub fn flat_map_test() {
  let testcase = fn(subject, f, expect) {
    subject
    |> stream.from_list
    |> stream.flat_map(f)
    |> stream.to_list
    |> should.equal(Ok(expect))
  }

  let f = fn(i) { stream.range(i, i + 2) }

  testcase([], f, [])
  testcase([1], f, [1, 2, 3])
  testcase([1, 2], f, [1, 2, 3, 2, 3, 4])
}

pub fn flatten_test() {
  let testcase = fn(lists) {
    lists
    |> list.map(stream.from_list)
    |> stream.from_list
    |> stream.flatten
    |> stream.to_list
    |> should.equal(Ok(list.flatten(lists)))
  }

  testcase([[], []])
  testcase([[1], [2]])
  testcase([[1, 2], [3, 4]])
}

pub fn emit_test() {
  let items = {
    use <- stream.emit(1)
    use <- stream.emit(2)
    use <- stream.emit(3)
    stream.empty()
  }

  items
  |> stream.to_list
  |> should.equal(Ok([1, 2, 3]))
}

pub fn emit_computes_only_necessary_values_test() {
  let items = {
    use <- stream.emit(1)
    use <- stream.emit(2)
    use <- stream.emit(3)
    stream.empty()
    panic as "yield computed more values than necessary"
  }

  items
  |> stream.take(3)
  |> stream.to_list
  |> should.equal(Ok([1, 2, 3]))
}

pub fn prepend_test() {
  stream.from_list([1, 2, 3])
  |> stream.prepend(0)
  |> stream.to_list
  |> should.equal(Ok([0, 1, 2, 3]))
}

pub fn transform_index_test() {
  let f = fn(i, el) { Next(#(i, el), i + 1) }

  ["a", "b", "c", "d"]
  |> stream.from_list
  |> stream.transform(0, f)
  |> stream.to_list
  |> should.equal(Ok([#(0, "a"), #(1, "b"), #(2, "c"), #(3, "d")]))
}

// -------------------------------
// Async Tests
// -------------------------------
pub fn async_map_test() {
  stream.from_list([1, 2, 3])
  |> stream.async
  |> stream.map(int.multiply(_, 2))
  |> stream.to_list
  |> should.equal(Ok([2, 4, 6]))
}
