import gleam/int
import gleeunit/should
import kino/stream/stream

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

pub fn async_map_test() {
  stream.from_list([1, 2, 3])
  |> stream.async_map(int.multiply(_, 2))
  |> stream.to_list
  |> should.equal(Ok([2, 4, 6]))
}
// pub fn filter_test() {
//   stream.from_list([1, 2, 3])
//   |> stream.filter(int.is_even)
//   |> stream.to_list
//   |> should.equal(Ok([2]))
// }

// pub fn repeat_test() {
//   stream.repeat(1)
//   |> stream.take(4)
//   |> stream.to_list
//   |> should.equal(Ok([1, 1, 1, 1]))
// }
