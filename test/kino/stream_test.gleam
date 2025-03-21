import gleam/erlang/process
import gleam/int
import gleam/list
import gleeunit/should
import kino/stream.{Next}

pub fn single_test() {
  stream.single(1)
  |> stream.to_list
  |> process.receive_forever
  |> should.equal(Ok([1]))
}

pub fn from_list_test() {
  stream.from_list([1, 2, 3])
  |> stream.to_list
  |> process.receive_forever
  |> should.equal(Ok([1, 2, 3]))
}

pub fn map_test() {
  stream.from_list([1, 2, 3])
  |> stream.map(int.multiply(_, 2))
  |> stream.to_list
  |> process.receive_forever
  |> should.equal(Ok([2, 4, 6]))
}

pub fn take_test() {
  let counter = stream.unfold(0, fn(acc) { stream.Next(acc, acc + 1) })
  counter
  |> stream.take(3)
  |> stream.to_list
  |> process.receive_forever
  |> should.equal(Ok([0, 1, 2]))
}

pub fn drop_test() {
  stream.range(0, 10)
  |> stream.drop(5)
  |> stream.to_list
  |> process.receive_forever
  |> should.equal([5, 6, 7, 8, 9, 10] |> Ok)
}

pub fn filter_test() {
  stream.from_list([1, 2, 3])
  |> stream.filter(int.is_even)
  |> stream.to_list
  |> process.receive_forever
  |> should.equal(Ok([2]))
}

pub fn filter_map_test() {
  let testcase = fn(subject, f) {
    subject
    |> stream.from_list
    |> stream.filter_map(f)
    |> stream.to_list
    |> process.receive_forever
    |> should.equal(list.filter_map(subject, f) |> Ok)
  }

  testcase([], int.parse)
  testcase(["1"], int.parse)
  testcase(["1", "2", "3"], int.parse)
  testcase(["1", "a", "b"], int.parse)
  testcase(["l", "2", "3", "a"], int.parse)
  testcase(["1", "c", "3", "a", "b"], int.parse)
  testcase(["1", "20", "ten", "4", "5", "69"], int.parse)
}

pub fn repeat_test() {
  stream.repeat(1)
  |> stream.take(4)
  |> stream.to_list
  |> process.receive_forever
  |> should.equal(Ok([1, 1, 1, 1]))
}

pub fn index_test() {
  stream.from_list(["a", "b", "c"])
  |> stream.index
  |> stream.to_list
  |> process.receive_forever
  |> should.equal(Ok([#("a", 0), #("b", 1), #("c", 2)]))
}

pub fn append_test() {
  stream.from_list([1, 2, 3])
  |> stream.append(stream.from_list([4, 5, 6]))
  |> stream.to_list
  |> process.receive_forever
  |> should.equal(Ok([1, 2, 3, 4, 5, 6]))

  stream.from_list([1, 2, 3])
  |> stream.map(int.multiply(_, 2))
  |> stream.append(
    stream.from_list([4, 5, 6]) |> stream.map(int.multiply(_, 2)),
  )
  |> stream.to_list
  |> process.receive_forever
  |> should.equal(Ok([2, 4, 6, 8, 10, 12]))

  stream.from_list([1, 2, 3])
  |> stream.async
  |> stream.map(int.multiply(_, 2))
  |> stream.append(
    stream.from_list([4, 5, 6]) |> stream.map(int.multiply(_, 2)),
  )
  |> stream.to_list
  |> process.receive_forever
  |> should.equal(Ok([2, 4, 6, 8, 10, 12]))

  stream.from_list([1, 2, 3])
  |> stream.map(int.multiply(_, 2))
  |> stream.append(
    stream.from_list([4, 5, 6])
    |> stream.async
    |> stream.map(int.multiply(_, 2)),
  )
  |> stream.to_list
  |> process.receive_forever
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
  |> process.receive_forever
  |> should.equal(Ok([2, 4, 6, 8, 10, 12]))
}

pub fn range_test() {
  let testcase = fn(a, b, expected) {
    stream.range(a, b)
    |> stream.to_list
    |> process.receive_forever
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
  |> process.receive_forever
  |> should.equal(Ok([1, 3, 9, 27, 81]))
}

pub fn take_while_test() {
  stream.from_list([1, 2, 3, 2, 4])
  |> stream.take_while(satisfying: fn(x) { x < 3 })
  |> stream.to_list
  |> process.receive_forever
  |> should.equal(Ok([1, 2]))
}

pub fn drop_while_test() {
  stream.from_list([1, 2, 3, 4, 2, 5])
  |> stream.drop_while(satisfying: fn(x) { x < 4 })
  |> stream.to_list
  |> process.receive_forever
  |> should.equal(Ok([4, 2, 5]))
}

pub fn zip_test() {
  stream.from_list(["a", "b", "c"])
  |> stream.zip(stream.range(20, 30))
  |> stream.to_list
  |> process.receive_forever
  |> should.equal([#("a", 20), #("b", 21), #("c", 22)] |> Ok)
}

pub fn flat_map_test() {
  let testcase = fn(subject, f, expect) {
    subject
    |> stream.from_list
    |> stream.flat_map(f)
    |> stream.to_list
    |> process.receive_forever
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
    |> process.receive_forever
    |> should.equal(Ok(list.flatten(lists)))
  }

  testcase([[], []])
  testcase([[1], [2]])
  testcase([[1, 2], [3, 4]])
}

pub fn concat_test() {
  let testcase = fn(lists) {
    lists
    |> list.map(stream.from_list)
    |> stream.concat
    |> stream.to_list
    |> process.receive_forever
    |> should.equal(list.flatten(lists) |> Ok)
  }

  testcase([[], []])
  testcase([[1], [2]])
  testcase([[1, 2], [3, 4]])
}

// TODO it always will end with the separator. Is that how other stream libraries behave?
pub fn intersperse_test() {
  stream.empty()
  |> stream.intersperse(with: 0)
  |> stream.to_list
  |> process.receive_forever
  |> should.equal(Ok([]))

  stream.from_list([1])
  |> stream.intersperse(with: 0)
  |> stream.to_list
  |> process.receive_forever
  |> should.equal(Ok([1, 0]))

  stream.from_list([1, 2, 3, 4, 5])
  |> stream.intersperse(with: 0)
  |> stream.to_list
  |> process.receive_forever
  |> should.equal(Ok([1, 0, 2, 0, 3, 0, 4, 0, 5, 0]))
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
  |> process.receive_forever
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
  |> process.receive_forever
  |> should.equal(Ok([1, 2, 3]))
}

pub fn prepend_test() {
  stream.from_list([1, 2, 3])
  |> stream.prepend(0)
  |> stream.to_list
  |> process.receive_forever
  |> should.equal(Ok([0, 1, 2, 3]))
}

pub fn transform_index_test() {
  let f = fn(i, el) { Next(#(i, el), i + 1) }

  ["a", "b", "c", "d"]
  |> stream.from_list
  |> stream.transform(0, f)
  |> stream.to_list
  |> process.receive_forever
  |> should.equal(Ok([#(0, "a"), #(1, "b"), #(2, "c"), #(3, "d")]))
}

pub fn interleave_test() {
  stream.from_list([1, 2, 3, 4])
  |> stream.interleave(with: stream.from_list([11, 12, 13, 14]))
  |> stream.to_list
  |> process.receive_forever
  |> should.equal([1, 11, 2, 12, 3, 13, 4, 14] |> Ok)

  stream.from_list([1, 2, 3, 4])
  |> stream.interleave(with: stream.from_list([100]))
  |> stream.to_list
  |> process.receive_forever
  |> should.equal([1, 100, 2, 3, 4] |> Ok)
}

pub fn try_fold_test() {
  let testcase = fn(
    subject: List(a),
    acc: acc,
    fun: fn(acc, a) -> Result(acc, err),
  ) {
    subject
    |> stream.from_list()
    |> stream.try_fold(acc, fun)
    |> process.receive_forever
    |> should.equal(Ok(list.try_fold(subject, acc, fun)))
  }

  let f = fn(e, acc) {
    case e % 2 {
      0 -> Ok(e + acc)
      _ -> Error("tried to add an odd number")
    }
  }
  testcase([], 0, f)
  testcase([2, 4, 6], 0, f)
  testcase([1, 2, 3], 0, f)
  testcase([1, 2, 3, 4, 5, 6, 7, 8], 0, f)

  [0, 2, 4, 6]
  |> stream.from_list()
  |> stream.try_fold(0, f)
  |> process.receive_forever
  |> should.equal(Ok(Ok(12)))

  [1, 2, 3, 4]
  |> stream.from_list()
  |> stream.try_fold(0, f)
  |> process.receive_forever
  |> should.equal(Ok(Error("tried to add an odd number")))
  // TCO test
  // stream.repeat(1)
  // |> stream.take(recursion_test_cycles)
  // |> stream.try_fold(0, fn(e, acc) { Ok(e + acc) })
  // |> process.receive_forever
}

// -------------------------------
// Async Tests
// -------------------------------
pub fn async_map_test() {
  stream.from_list([1, 2, 3])
  |> stream.async
  |> stream.map(int.multiply(_, 2))
  |> stream.to_list
  |> process.receive_forever
  |> should.equal(Ok([2, 4, 6]))
}
