import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/otp/task
import gleeunit/should
import kino/stream2.{Next} as stream

pub fn single_test() {
  stream.single(1)
  |> stream.to_list
  |> task.await_forever
  |> should.equal([1])
}

pub fn from_list_test() {
  stream.from_list([1, 2, 3])
  |> stream.to_list
  |> task.await_forever
  |> should.equal([1, 2, 3])
}

pub fn map_test() {
  stream.from_list([1, 2, 3])
  |> stream.map(int.multiply(_, 2))
  |> stream.to_list
  |> task.await_forever
  |> should.equal([2, 4, 6])
}

pub fn take_test() {
  let counter = stream.unfold(0, fn(acc) { stream.Next(acc, acc + 1) })
  counter
  |> stream.take(3)
  |> stream.to_list
  |> task.await_forever
  |> should.equal([0, 1, 2])
}

pub fn drop_test() {
  stream.range(0, 10)
  |> stream.drop(5)
  |> stream.to_list
  |> task.await_forever
  |> should.equal([5, 6, 7, 8, 9, 10])
}

pub fn filter_test() {
  stream.from_list([1, 2, 3])
  |> stream.filter(int.is_even)
  |> stream.to_list
  |> task.await_forever
  |> should.equal([2])
}

pub fn filter_map_test() {
  let testcase = fn(subject, f) {
    subject
    |> stream.from_list
    |> stream.filter_map(f)
    |> stream.to_list
    |> task.await_forever
    |> should.equal(list.filter_map(subject, f))
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
  |> task.await_forever
  |> should.equal([1, 1, 1, 1])
}

pub fn index_test() {
  stream.from_list(["a", "b", "c"])
  |> stream.index
  |> stream.to_list
  |> task.await_forever
  |> should.equal([#("a", 0), #("b", 1), #("c", 2)])
}

// pub fn append_test() {
//   stream.from_list([1, 2, 3])
//   |> stream.append(stream.from_list([4, 5, 6]))
//   |> stream.to_list
//   |> task.await_forever
//   |> should.equal([1, 2, 3, 4, 5, 6])

//   stream.from_list([1, 2, 3])
//   |> stream.map(int.multiply(_, 2))
//   |> stream.append(
//     stream.from_list([4, 5, 6]) |> stream.map(int.multiply(_, 2)),
//   )
//   |> stream.to_list
//   |> task.await_forever
//   |> should.equal([2, 4, 6, 8, 10, 12])

//   stream.from_list([1, 2, 3])
//   |> stream.async
//   |> stream.map(int.multiply(_, 2))
//   |> stream.append(
//     stream.from_list([4, 5, 6]) |> stream.map(int.multiply(_, 2)),
//   )
//   |> stream.to_list
//   |> task.await_forever
//   |> should.equal([2, 4, 6, 8, 10, 12])

//   stream.from_list([1, 2, 3])
//   |> stream.map(int.multiply(_, 2))
//   |> stream.append(
//     stream.from_list([4, 5, 6])
//     |> stream.async
//     |> stream.map(int.multiply(_, 2)),
//   )
//   |> stream.to_list
//   |> task.await_forever
//   |> should.equal([2, 4, 6, 8, 10, 12])

//   stream.from_list([1, 2, 3])
//   |> stream.async
//   |> stream.map(int.multiply(_, 2))
//   |> stream.append(
//     stream.from_list([4, 5, 6])
//     |> stream.async
//     |> stream.map(int.multiply(_, 2)),
//   )
//   |> stream.to_list
//   |> task.await_forever
//   |> should.equal([2, 4, 6, 8, 10, 12])
// }

pub fn range_test() {
  let testcase = fn(a, b, expected) {
    stream.range(a, b)
    |> stream.to_list
    |> task.await_forever
    |> should.equal(expected)
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
  |> task.await_forever
  |> should.equal([1, 3, 9, 27, 81])
}

pub fn take_while_test() {
  stream.from_list([1, 2, 3, 2, 4])
  |> stream.take_while(satisfying: fn(x) { x < 3 })
  |> stream.to_list
  |> task.await_forever
  |> should.equal([1, 2])
}

pub fn drop_while_test() {
  stream.from_list([1, 2, 3, 4, 2, 5])
  |> stream.drop_while(satisfying: fn(x) { x < 4 })
  |> stream.to_list
  |> task.await_forever
  |> should.equal([4, 2, 5])
}

pub fn zip_test() {
  stream.from_list(["a", "b", "c"])
  |> stream.zip(stream.range(20, 30))
  |> stream.to_list
  |> task.await_forever
  |> should.equal([#("a", 20), #("b", 21), #("c", 22)])
}

pub fn flat_map_test() {
  let testcase = fn(subject, f, expect) {
    subject
    |> stream.from_list
    |> stream.flat_map(f)
    |> stream.to_list
    |> task.await_forever
    |> should.equal(expect)
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
    |> task.await_forever
    |> should.equal(list.flatten(lists))
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
    |> task.await_forever
    |> should.equal(list.flatten(lists))
  }

  testcase([[], []])
  testcase([[1], [2]])
  testcase([[1, 2], [3, 4]])
}

pub fn intersperse_test() {
  stream.empty()
  |> stream.intersperse(with: 0)
  |> stream.to_list
  |> task.await_forever
  |> should.equal([])

  stream.from_list([1])
  |> stream.intersperse(with: 0)
  |> stream.to_list
  |> task.await_forever
  |> should.equal([1])

  stream.from_list([1, 2, 3, 4, 5])
  |> stream.intersperse(with: 0)
  |> stream.to_list
  |> task.await_forever
  |> should.equal([1, 0, 2, 0, 3, 0, 4, 0, 5])
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
  |> task.await_forever
  |> should.equal([1, 2, 3])
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
  |> task.await_forever
  |> should.equal([1, 2, 3])
}

pub fn prepend_test() {
  stream.from_list([1, 2, 3])
  |> stream.prepend(0)
  |> stream.to_list
  |> task.await_forever
  |> should.equal([0, 1, 2, 3])
}

pub fn transform_index_test() {
  let f = fn(i, el) { Next(#(i, el), i + 1) }

  ["a", "b", "c", "d"]
  |> stream.from_list
  |> stream.transform(0, f)
  |> stream.to_list
  |> task.await_forever
  |> should.equal([#(0, "a"), #(1, "b"), #(2, "c"), #(3, "d")])
}

pub fn interleave_test() {
  stream.from_list([1, 2, 3, 4])
  |> stream.interleave(with: stream.from_list([11, 12, 13, 14]))
  |> stream.to_list
  |> task.await_forever
  |> should.equal([1, 11, 2, 12, 3, 13, 4, 14])

  stream.from_list([1, 2, 3, 4])
  |> stream.interleave(with: stream.from_list([100]))
  |> stream.to_list
  |> task.await_forever
  |> should.equal([1, 100, 2, 3, 4])
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
    |> task.await_forever
    |> should.equal(list.try_fold(subject, acc, fun))
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
  |> task.await_forever
  |> should.equal(Ok(12))

  [1, 2, 3, 4]
  |> stream.from_list()
  |> stream.try_fold(0, f)
  |> task.await_forever
  |> should.equal(Error("tried to add an odd number"))
  // TCO test
  // stream.repeat(1)
  // |> stream.take(recursion_test_cycles)
  // |> stream.try_fold(0, fn(e, acc) { e + acc })
  // |> task.await_forever
}

pub fn buffer_test() {
  stream.from_list([1, 2, 3])
  |> stream.map(fn(i) { int.multiply(i, 2) })
  |> stream.buffer(3)
  |> stream.to_list
  |> task.await(20)
  |> should.equal([2, 4, 6])
}

// -------------------------------
// Async Tests
// -------------------------------
// pub fn async_map_test() {
//   list.range(1, 10)
//   |> stream.from_list
//   |> stream.async_map(3, fn(i) { int.multiply(i, 2) })
//   |> stream.to_list
//   |> task.await_forever
//   |> list.sort(int.compare)
//   |> should.equal([2, 4, 6, 8, 10, 12, 14, 16, 18, 20])
// }

pub fn par_map_test() {
  list.range(1, 10)
  |> stream.from_list
  |> stream.par_map(3, fn(i) { int.multiply(i, 2) })
  |> stream.to_list
  |> task.await_forever
  |> list.sort(int.compare)
  |> should.equal([2, 4, 6, 8, 10, 12, 14, 16, 18, 20])
}

pub fn async_interleave_test() {
  [1, 3, 5, 7, 9, 11]
  |> stream.from_list
  |> stream.async_interleave(stream.from_list([2, 4, 6]))
  |> stream.to_list
  |> task.await_forever
  |> should.equal([1, 2, 3, 4, 5, 6, 7, 9, 11])
}

// pub fn async_concat_test() {
//   // Create multiple streams to concatenate
//   let streams = [
//     stream.from_list([1, 2, 3]),
//     stream.from_list([4, 5, 6]),
//     stream.from_list([7, 8, 9]),
//     stream.from_list([10, 11, 12]),
//   ]

//   // Test with max_open=2 (process 2 streams concurrently)
//   streams
//   |> stream.async_concat(2)
//   |> stream.to_list
//   |> task.await_forever
//   |> list.sort(int.compare)
//   |> should.equal([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
//   // Also test with empty streams in the mix
//   let mixed_streams = [
//     stream.from_list([1, 2]),
//     stream.empty(),
//     stream.from_list([3, 4]),
//     stream.empty(),
//     stream.from_list([5, 6]),
//   ]

//   mixed_streams
//   |> stream.async_concat(3)
//   |> stream.to_list
//   |> task.await_forever
//   |> list.sort(int.compare)
//   |> should.equal([1, 2, 3, 4, 5, 6])

//   // Test with empty list
//   []
//   |> stream.async_concat(2)
//   |> stream.to_list
//   |> task.await_forever
//   |> should.equal([])

//   // Test with single stream
//   [stream.from_list([1, 2, 3])]
//   |> stream.async_concat(2)
//   |> stream.to_list
//   |> task.await_forever
//   |> should.equal([1, 2, 3])
//   // Test with a large number of streams
//   list.range(1, 10)
//   |> list.map(fn(i) { stream.from_list([i * 10, i * 10 + 1]) })
//   |> stream.async_concat(3)
//   |> stream.to_list
//   |> task.await_forever
//   |> list.sort(int.compare)
//   |> should.equal([
//     10, 11, 20, 21, 30, 31, 40, 41, 50, 51, 60, 61, 70, 71, 80, 81, 90, 91, 100,
//     101,
//   ])
// }

pub fn par_concat_test() {
  // Create multiple streams to concatenate
  let streams = [
    stream.from_list([1, 2, 3]),
    stream.from_list([4, 5, 6]),
    stream.from_list([7, 8, 9]),
    stream.from_list([10, 11, 12]),
  ]
  // Test with max_open=2 (process 2 streams concurrently)
  streams
  |> stream.par_concat(2)
  |> stream.to_list
  |> task.await_forever
  |> list.sort(int.compare)
  |> should.equal([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
  // Also test with empty streams in the mix
  let mixed_streams = [
    stream.from_list([1, 2]),
    stream.empty(),
    stream.from_list([3, 4]),
    stream.empty(),
    stream.from_list([5, 6]),
  ]
  mixed_streams
  |> stream.par_concat(3)
  |> stream.to_list
  |> task.await_forever
  |> list.sort(int.compare)
  |> should.equal([1, 2, 3, 4, 5, 6])
  // Test with empty list
  []
  |> stream.par_concat(2)
  |> stream.to_list
  |> task.await_forever
  |> should.equal([])
  // Test with single stream
  [stream.from_list([1, 2, 3])]
  |> stream.par_concat(2)
  |> stream.to_list
  |> task.await_forever
  |> should.equal([1, 2, 3])
  // Test with a large number of streams
  list.range(1, 10)
  |> list.map(fn(i) { stream.from_list([i * 10, i * 10 + 1]) })
  |> stream.par_concat(3)
  |> stream.to_list
  |> task.await_forever
  |> list.sort(int.compare)
  |> should.equal([
    10, 11, 20, 21, 30, 31, 40, 41, 50, 51, 60, 61, 70, 71, 80, 81, 90, 91, 100,
    101,
  ])
}

pub fn async_flatten_test() {
  // Create multiple streams to concatenate
  let streams =
    stream.from_list([
      stream.from_list([1, 2, 3]),
      stream.from_list([4, 5, 6]),
      stream.from_list([7, 8, 9]),
      stream.from_list([10, 11, 12]),
    ])
  // Test with max_open=2 (process 2 streams concurrently)
  streams
  |> stream.async_flatten(2)
  |> stream.to_list
  |> task.await_forever
  |> list.sort(int.compare)
  |> should.equal([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
  // Also test with empty streams in the mix
  let mixed_streams =
    stream.from_list([
      stream.from_list([1, 2]),
      stream.empty(),
      stream.from_list([3, 4]),
      stream.empty(),
      stream.from_list([5, 6]),
    ])
  mixed_streams
  |> stream.async_flatten(3)
  |> stream.to_list
  |> task.await_forever
  |> list.sort(int.compare)
  |> should.equal([1, 2, 3, 4, 5, 6])
  // Test with empty list
  stream.empty()
  |> stream.async_flatten(2)
  |> stream.to_list
  |> task.await_forever
  |> should.equal([])
  // Test with single stream
  stream.from_list([stream.from_list([1, 2, 3])])
  |> stream.async_flatten(2)
  |> stream.to_list
  |> task.await_forever
  |> should.equal([1, 2, 3])
  // Test with a large number of streams
  list.range(1, 10)
  |> list.map(fn(i) { stream.from_list([i * 10, i * 10 + 1]) })
  |> stream.from_list
  |> stream.async_flatten(3)
  |> stream.to_list
  |> task.await_forever
  |> list.sort(int.compare)
  |> should.equal([
    10, 11, 20, 21, 30, 31, 40, 41, 50, 51, 60, 61, 70, 71, 80, 81, 90, 91, 100,
    101,
  ])
}

pub fn async_filter_test() {
  // Test with empty stream
  stream.empty()
  |> stream.async_filter(3, fn(_) { True })
  |> stream.to_list
  |> task.await_forever
  |> should.equal([])

  // Basic filtering - even numbers
  list.range(1, 10)
  |> stream.from_list
  |> stream.async_filter(3, int.is_even)
  |> stream.to_list
  |> task.await_forever
  |> list.sort(int.compare)
  // Sort because parallelism might affect order
  |> should.equal([2, 4, 6, 8, 10])

  // Filter all elements out
  list.range(1, 10)
  |> stream.from_list
  |> stream.async_filter(3, fn(_) { False })
  |> stream.to_list
  |> task.await_forever
  |> should.equal([])

  // Filter no elements out
  list.range(1, 10)
  |> stream.from_list
  |> stream.async_filter(3, fn(_) { True })
  |> stream.to_list
  |> task.await_forever
  |> list.sort(int.compare)
  |> should.equal(list.range(1, 10))

  // Test with single worker (should behave like regular filter)
  list.range(1, 10)
  |> stream.from_list
  |> stream.async_filter(1, int.is_even)
  |> stream.to_list
  |> task.await_forever
  |> should.equal([2, 4, 6, 8, 10])

  // Test with larger stream and more workers to ensure parallelism works
  let larger_stream = list.range(1, 100)
  let result =
    larger_stream
    |> stream.from_list
    |> stream.async_filter(8, int.is_even)
    |> stream.to_list
    |> task.await_forever
    |> list.sort(int.compare)

  // Create the expected result (all even numbers from 1 to 100)
  let expected =
    larger_stream
    |> list.filter(int.is_even)

  result
  |> should.equal(expected)

  // Test with a predicate that takes time to compute
  // This helps ensure that parallelism is actually happening
  let slow_predicate = fn(x) {
    process.sleep(5)
    int.is_even(x)
  }

  // With parallelism, this should complete faster than sequential processing
  list.range(1, 20)
  |> stream.from_list
  |> stream.async_filter(5, slow_predicate)
  |> stream.to_list
  |> task.await(300)
  // Should complete within timeout with parallelism
  |> list.sort(int.compare)
  |> should.equal([2, 4, 6, 8, 10, 12, 14, 16, 18, 20])

  // Fallback to regular filter when workers <= 1
  // Test that it behaves the same as regular filter
  let reference =
    list.range(1, 10)
    |> stream.from_list
    |> stream.filter(int.is_even)
    |> stream.to_list
    |> task.await_forever

  list.range(1, 10)
  |> stream.from_list
  |> stream.async_filter(0, int.is_even)
  // 0 workers should fall back to regular filter
  |> stream.to_list
  |> task.await_forever
  |> should.equal(reference)
}
