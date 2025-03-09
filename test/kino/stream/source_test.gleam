// import gleam/int
// import gleeunit/should
// import kino/stream/source

// pub fn single_test() {
//   source.single(1)
//   |> source.to_list
//   |> should.equal(Ok([1]))
// }

// pub fn from_list_test() {
//   source.from_list([1, 2, 3])
//   |> source.to_list
//   |> should.equal(Ok([1, 2, 3]))
// }

// pub fn map_test() {
//   source.from_list([1, 2, 3])
//   |> source.map(int.multiply(_, 2))
//   |> source.to_list
//   |> should.equal(Ok([2, 4, 6]))
// }

// pub fn take_test() {
//   let counter = source.unfold(0, fn(acc) { source.Next([acc], acc + 1) })
//   counter
//   |> source.take(3)
//   |> source.to_list
//   |> should.equal(Ok([0, 1, 2]))
// }

// pub fn filter_test() {
//   source.from_list([1, 2, 3])
//   |> source.filter(int.is_even)
//   |> source.to_list
//   |> should.equal(Ok([2]))
// }

// pub fn repeat_test() {
//   source.repeat(1)
//   |> source.take(4)
//   |> source.to_list
//   |> should.equal(Ok([1, 1, 1, 1]))
// }
// // import gleam/dict
// // import gleam/int
// // import gleam/list
// // import gleeunit
// // import gleeunit/should
// // import kino/stream/source.{Done, Next}

// // pub fn main() {
// //   gleeunit.main()
// // }

// // @target(erlang)
// // const recursion_test_cycles = 1_000_000

// // // JavaScript engines crash when exceeding a certain stack size:
// // //
// // // - Chrome 106 and NodeJS V16, V18, and V19 crash around 10_000+
// // // - Firefox 106 crashes around 35_000+.
// // // - Safari 16 crashes around 40_000+.
// // @target(javascript)
// // const recursion_test_cycles = 40_000

// // // a |> from_list |> to_list == a
// // pub fn to_from_list_test() {
// //   let testcase = fn(subject) {
// //     subject
// //     |> source.from_list
// //     |> source.to_list
// //     |> should.equal(subject)
// //   }

// //   testcase([])
// //   testcase([1])
// //   testcase([1, 2])
// //   testcase([1, 2, 4, 8])
// // }

// // pub fn step_test() {
// //   let testcase = fn(subject) {
// //     let step =
// //       subject
// //       |> source.from_list
// //       |> source.step

// //     case subject {
// //       [] ->
// //         step
// //         |> should.equal(Done)

// //       [h, ..t] -> {
// //         let assert Next(h2, t2) = step
// //         h
// //         |> should.equal(h2)
// //         t2
// //         |> source.to_list
// //         |> should.equal(t)
// //       }
// //     }
// //   }

// //   testcase([])
// //   testcase([1])
// //   testcase([1, 2])
// //   testcase([1, 2, 3])
// // }

// // // a |> from_list |> take(n) == a |> list.take(_, n)
// // pub fn take_test() {
// //   let testcase = fn(n, subject) {
// //     subject
// //     |> source.from_list
// //     |> source.take(n)
// //     |> source.to_list
// //     |> should.equal(list.take(subject, n))
// //   }

// //   testcase(0, [])
// //   testcase(1, [])
// //   testcase(-1, [])
// //   testcase(0, [0])
// //   testcase(1, [0])
// //   testcase(-1, [0])
// //   testcase(0, [0, 1, 2, 3, 4])
// //   testcase(1, [0, 1, 2, 3, 4])
// //   testcase(2, [0, 1, 2, 3, 4])
// //   testcase(22, [0, 1, 2, 3, 4])
// // }

// // pub fn transform_index_test() {
// //   let f = fn(i, el) { Next(#(i, el), i + 1) }

// //   ["a", "b", "c", "d"]
// //   |> source.from_list
// //   |> source.transform(0, f)
// //   |> source.to_list
// //   |> should.equal([#(0, "a"), #(1, "b"), #(2, "c"), #(3, "d")])
// // }

// // pub fn transform_take_test() {
// //   let f = fn(rem, el) {
// //     case rem > 0 {
// //       False -> Done
// //       True -> Next(el, rem - 1)
// //     }
// //   }

// //   [1, 2, 3, 4, 5]
// //   |> source.from_list
// //   |> source.transform(3, f)
// //   |> source.to_list
// //   |> should.equal([1, 2, 3])
// // }

// // pub fn transform_take_while_test() {
// //   let f = fn(_, el) {
// //     case el < 3 {
// //       True -> Next(el, Nil)
// //       False -> Done
// //     }
// //   }

// //   [1, 2, 3, 2, 4]
// //   |> source.from_list
// //   |> source.transform(Nil, f)
// //   |> source.to_list
// //   |> should.equal([1, 2])
// // }

// // pub fn transform_scan_test() {
// //   let f = fn(acc, el) {
// //     let result = acc + el
// //     Next(result, result)
// //   }

// //   [1, 2, 3, 4, 5]
// //   |> source.from_list
// //   |> source.transform(0, f)
// //   |> source.to_list
// //   |> should.equal([1, 3, 6, 10, 15])
// // }

// // // a |> from_list |> fold(a, f) == a |> list.fold(_, a, f)
// // pub fn fold_test() {
// //   let testcase = fn(subject, acc, f) {
// //     subject
// //     |> source.from_list
// //     |> source.fold(acc, f)
// //     |> should.equal(list.fold(subject, acc, f))
// //   }

// //   let f = fn(acc, e) { [e, ..acc] }
// //   testcase([], [], f)
// //   testcase([1], [], f)
// //   testcase([1, 2, 3], [], f)
// //   testcase([1, 2, 3, 4, 5, 6, 7, 8], [], f)
// // }

// // // a |> from_list |> map(f) |> to_list == a |> list.map(_, f)
// // pub fn map_test() {
// //   let testcase = fn(subject, f) {
// //     subject
// //     |> source.from_list
// //     |> source.map(f)
// //     |> source.to_list
// //     |> should.equal(list.map(subject, f))
// //   }

// //   let f = fn(e) { e * 2 }
// //   testcase([], f)
// //   testcase([1], f)
// //   testcase([1, 2, 3], f)
// //   testcase([1, 2, 3, 4, 5, 6, 7, 8], f)
// // }

// // // map2(from_list(a), from_list(b), f)  == list.map2(a, b, f)
// // pub fn map2_test() {
// //   let testcase = fn(one, other, f) {
// //     source.map2(source.from_list(one), source.from_list(other), f)
// //     |> source.to_list
// //     |> should.equal(list.map2(one, other, f))
// //   }

// //   let f = fn(a, b) { a / b }
// //   testcase([], [], f)
// //   testcase([], [2, 10, 3], f)
// //   testcase([10], [2, 10, 3], f)
// //   testcase([10, 20], [2, 10, 3], f)
// //   testcase([10, 20, 30], [2, 10, 3], f)
// //   testcase([10, 20, 30], [2, 10], f)
// //   testcase([10, 20, 30], [2], f)
// //   testcase([10, 20, 30], [], f)
// // }

// // pub fn map2_is_lazy_test() {
// //   let one = source.from_list([])
// //   let other = source.once(fn() { panic as "unreachable" })

// //   source.map2(one, other, fn(x, y) { x + y })
// //   |> source.to_list
// //   |> should.equal([])
// // }

// // // a |> from_list |> flat_map(f) |> to_list ==
// // //   a |> list.map(f) |> list.map(to_list) |> list.concat
// // pub fn flat_map_test() {
// //   let testcase = fn(subject, f) {
// //     subject
// //     |> source.from_list
// //     |> source.flat_map(f)
// //     |> source.to_list
// //     |> should.equal(
// //       subject
// //       |> list.map(f)
// //       |> list.map(source.to_list)
// //       |> list.flatten,
// //     )
// //   }

// //   let f = fn(i) { source.range(i, i + 2) }

// //   testcase([], f)
// //   testcase([1], f)
// //   testcase([1, 2], f)
// // }

// // // a |> from_list |> append(from_list(b)) |> to_list == list.concat([a, b])
// // pub fn append_test() {
// //   let testcase = fn(left, right) {
// //     left
// //     |> source.from_list
// //     |> source.append(source.from_list(right))
// //     |> source.to_list
// //     |> should.equal(list.flatten([left, right]))
// //   }

// //   testcase([], [])
// //   testcase([1], [2])
// //   testcase([1, 2], [3, 4])
// // }

// // // a |> list.map(from_list) |> from_list |> flatten |> to_list == list.concat(a)
// // pub fn flatten_test() {
// //   let testcase = fn(lists) {
// //     lists
// //     |> list.map(source.from_list)
// //     |> source.from_list
// //     |> source.flatten
// //     |> source.to_list
// //     |> should.equal(list.flatten(lists))
// //   }

// //   testcase([[], []])
// //   testcase([[1], [2]])
// //   testcase([[1, 2], [3, 4]])
// // }

// // // a |> list.map(from_list) |> concat |> to_list == list.concat(a)
// // pub fn concat_test() {
// //   let testcase = fn(lists) {
// //     lists
// //     |> list.map(source.from_list)
// //     |> source.concat
// //     |> source.to_list
// //     |> should.equal(list.flatten(lists))
// //   }

// //   testcase([[], []])
// //   testcase([[1], [2]])
// //   testcase([[1, 2], [3, 4]])
// // }

// // // a |> from_list |> filter(f) |> to_list == a |> list.filter(_, f)
// // pub fn filter_test() {
// //   let testcase = fn(subject, f) {
// //     subject
// //     |> source.from_list
// //     |> source.filter(f)
// //     |> source.to_list
// //     |> should.equal(list.filter(subject, f))
// //   }

// //   let even = fn(x) { x % 2 == 0 }
// //   testcase([], even)
// //   testcase([1], even)
// //   testcase([1, 2], even)
// //   testcase([1, 2, 3], even)
// //   testcase([1, 2, 3, 4], even)
// //   testcase([1, 2, 3, 4, 5], even)
// //   testcase([1, 2, 3, 4, 5, 6], even)
// // }

// // pub fn filter_map_test() {
// //   let testcase = fn(subject, f) {
// //     subject
// //     |> source.from_list
// //     |> source.filter_map(f)
// //     |> source.to_list
// //     |> should.equal(list.filter_map(subject, f))
// //   }

// //   testcase([], int.parse)
// //   testcase(["1"], int.parse)
// //   testcase(["1", "2", "3"], int.parse)
// //   testcase(["1", "a", "b"], int.parse)
// //   testcase(["l", "2", "3", "a"], int.parse)
// //   testcase(["1", "c", "3", "a", "b"], int.parse)
// //   testcase(["1", "20", "ten", "4", "5", "69"], int.parse)
// // }

// // pub fn repeat_test() {
// //   1
// //   |> source.repeat
// //   |> source.take(5)
// //   |> source.to_list
// //   |> should.equal([1, 1, 1, 1, 1])
// // }

// // pub fn cycle_test() {
// //   [1, 2, 3]
// //   |> source.from_list
// //   |> source.cycle
// //   |> source.take(9)
// //   |> source.to_list
// //   |> should.equal([1, 2, 3, 1, 2, 3, 1, 2, 3])
// // }

// // pub fn unfold_test() {
// //   source.unfold(2, fn(acc) { source.Next(acc, acc * 2) })
// //   |> source.take(5)
// //   |> source.to_list
// //   |> should.equal([2, 4, 8, 16, 32])

// //   source.unfold(2, fn(_) { source.Done })
// //   |> source.take(5)
// //   |> source.to_list
// //   |> should.equal([])

// //   fn(n) {
// //     case n {
// //       0 -> source.Done
// //       n -> source.Next(element: n, accumulator: n - 1)
// //     }
// //   }
// //   |> source.unfold(from: 5)
// //   |> source.to_list
// //   |> should.equal([5, 4, 3, 2, 1])
// // }

// // pub fn range_test() {
// //   let testcase = fn(a, b, expected) {
// //     source.range(a, b)
// //     |> source.to_list
// //     |> should.equal(expected)
// //   }

// //   testcase(0, 0, [0])
// //   testcase(1, 1, [1])
// //   testcase(-1, -1, [-1])
// //   testcase(0, 1, [0, 1])
// //   testcase(0, 5, [0, 1, 2, 3, 4, 5])
// //   testcase(1, -5, [1, 0, -1, -2, -3, -4, -5])
// // }

// // pub fn drop_test() {
// //   source.range(0, 10)
// //   |> source.drop(5)
// //   |> source.to_list
// //   |> should.equal([5, 6, 7, 8, 9, 10])
// // }

// // type Cat {
// //   Cat(id: Int)
// // }

// // pub fn find_test() {
// //   source.range(0, 10)
// //   |> source.find(fn(e) { e == 5 })
// //   |> should.equal(Ok(5))

// //   source.range(0, 10)
// //   |> source.find(fn(e) { e > 10 })
// //   |> should.equal(Error(Nil))

// //   source.empty()
// //   |> source.find(fn(_x) { True })
// //   |> should.equal(Error(Nil))

// //   source.unfold(Cat(id: 1), fn(cat: Cat) {
// //     source.Next(cat, Cat(id: cat.id + 1))
// //   })
// //   |> source.find(fn(cat: Cat) { cat.id == 10 })
// //   |> should.equal(Ok(Cat(id: 10)))
// // }

// // pub fn find_map_test() {
// //   source.range(0, 10)
// //   |> source.find_map(fn(e) {
// //     case e == 5 {
// //       True -> Ok(e)
// //       False -> Error(Nil)
// //     }
// //   })
// //   |> should.equal(Ok(5))

// //   source.range(0, 10)
// //   |> source.find_map(fn(e) {
// //     case e > 10 {
// //       True -> Ok(e)
// //       False -> Error(Nil)
// //     }
// //   })
// //   |> should.equal(Error(Nil))

// //   source.empty()
// //   |> source.find_map(fn(_x) { Ok(True) })
// //   |> should.equal(Error(Nil))

// //   source.unfold(Cat(id: 1), fn(cat: Cat) {
// //     source.Next(cat, Cat(id: cat.id + 1))
// //   })
// //   |> source.find_map(fn(cat: Cat) {
// //     case cat.id == 10 {
// //       True -> Ok(cat)
// //       False -> Error(Nil)
// //     }
// //   })
// //   |> should.equal(Ok(Cat(id: 10)))
// // }

// // pub fn index_test() {
// //   source.from_list(["a", "b", "c"])
// //   |> source.index
// //   |> source.to_list
// //   |> should.equal([#("a", 0), #("b", 1), #("c", 2)])
// // }

// // pub fn iterate_test() {
// //   fn(x) { x * 3 }
// //   |> source.iterate(from: 1)
// //   |> source.take(5)
// //   |> source.to_list
// //   |> should.equal([1, 3, 9, 27, 81])
// // }

// // pub fn take_while_test() {
// //   source.from_list([1, 2, 3, 2, 4])
// //   |> source.take_while(satisfying: fn(x) { x < 3 })
// //   |> source.to_list
// //   |> should.equal([1, 2])
// // }

// // pub fn drop_while_test() {
// //   source.from_list([1, 2, 3, 4, 2, 5])
// //   |> source.drop_while(satisfying: fn(x) { x < 4 })
// //   |> source.to_list
// //   |> should.equal([4, 2, 5])
// // }

// // pub fn scan_test() {
// //   source.from_list([1, 2, 3, 4, 5])
// //   |> source.scan(from: 0, with: fn(acc, el) { acc + el })
// //   |> source.to_list
// //   |> should.equal([1, 3, 6, 10, 15])
// // }

// // pub fn zip_test() {
// //   source.from_list(["a", "b", "c"])
// //   |> source.zip(source.range(20, 30))
// //   |> source.to_list
// //   |> should.equal([#("a", 20), #("b", 21), #("c", 22)])
// // }

// // pub fn chunk_test() {
// //   source.from_list([1, 2, 2, 3, 4, 4, 6, 7, 7])
// //   |> source.chunk(by: fn(n) { n % 2 })
// //   |> source.to_list
// //   |> should.equal([[1], [2, 2], [3], [4, 4, 6], [7, 7]])
// // }

// // pub fn sized_chunk_test() {
// //   source.from_list([1, 2, 3, 4, 5, 6])
// //   |> source.sized_chunk(into: 2)
// //   |> source.to_list
// //   |> should.equal([[1, 2], [3, 4], [5, 6]])

// //   source.from_list([1, 2, 3, 4, 5, 6, 7, 8])
// //   |> source.sized_chunk(into: 3)
// //   |> source.to_list
// //   |> should.equal([[1, 2, 3], [4, 5, 6], [7, 8]])
// // }

// // pub fn intersperse_test() {
// //   source.empty()
// //   |> source.intersperse(with: 0)
// //   |> source.to_list
// //   |> should.equal([])

// //   source.from_list([1])
// //   |> source.intersperse(with: 0)
// //   |> source.to_list
// //   |> should.equal([1])

// //   source.from_list([1, 2, 3, 4, 5])
// //   |> source.intersperse(with: 0)
// //   |> source.to_list
// //   |> should.equal([1, 0, 2, 0, 3, 0, 4, 0, 5])
// // }

// // pub fn any_test() {
// //   source.empty()
// //   |> source.any(satisfying: fn(n) { n % 2 == 0 })
// //   |> should.be_false

// //   source.from_list([1, 2, 5, 7, 9])
// //   |> source.any(satisfying: fn(n) { n % 2 == 0 })
// //   |> should.be_true

// //   source.from_list([1, 3, 5, 7, 9])
// //   |> source.any(satisfying: fn(n) { n % 2 == 0 })
// //   |> should.be_false

// //   // TCO test
// //   source.repeat(1)
// //   |> source.take(recursion_test_cycles)
// //   |> source.any(satisfying: fn(n) { n % 2 == 0 })
// //   |> should.be_false
// // }

// // pub fn all_test() {
// //   source.empty()
// //   |> source.all(satisfying: fn(n) { n % 2 == 0 })
// //   |> should.be_true

// //   source.from_list([2, 4, 6, 8])
// //   |> source.all(satisfying: fn(n) { n % 2 == 0 })
// //   |> should.be_true

// //   source.from_list([2, 4, 5, 8])
// //   |> source.all(satisfying: fn(n) { n % 2 == 0 })
// //   |> should.be_false

// //   // TCO test
// //   source.repeat(0)
// //   |> source.take(recursion_test_cycles)
// //   |> source.all(satisfying: fn(n) { n % 2 == 0 })
// //   |> should.be_true
// // }

// // pub fn group_test() {
// //   source.from_list([1, 2, 3, 4, 5, 6])
// //   |> source.group(by: fn(n) { n % 3 })
// //   |> should.equal(dict.from_list([#(0, [3, 6]), #(1, [1, 4]), #(2, [2, 5])]))
// // }

// // pub fn reduce_test() {
// //   source.empty()
// //   |> source.reduce(with: fn(acc, x) { acc + x })
// //   |> should.equal(Error(Nil))

// //   source.from_list([1, 2, 3, 4, 5])
// //   |> source.reduce(with: fn(acc, x) { acc + x })
// //   |> should.equal(Ok(15))
// // }

// // pub fn last_test() {
// //   source.empty()
// //   |> source.last
// //   |> should.equal(Error(Nil))

// //   source.range(1, 10)
// //   |> source.last
// //   |> should.equal(Ok(10))
// // }

// // pub fn empty_test() {
// //   source.empty()
// //   |> source.to_list
// //   |> should.equal([])
// // }

// // pub fn once_test() {
// //   source.once(fn() { 1 })
// //   |> source.to_list
// //   |> should.equal([1])
// // }

// // pub fn single_test() {
// //   source.single(1)
// //   |> source.to_list
// //   |> should.equal([1])
// // }

// // pub fn interleave_test() {
// //   source.from_list([1, 2, 3, 4])
// //   |> source.interleave(with: source.from_list([11, 12, 13, 14]))
// //   |> source.to_list
// //   |> should.equal([1, 11, 2, 12, 3, 13, 4, 14])

// //   source.from_list([1, 2, 3, 4])
// //   |> source.interleave(with: source.from_list([100]))
// //   |> source.to_list
// //   |> should.equal([1, 100, 2, 3, 4])
// // }

// // // a |> from_list |> fold_until(acc, f) == a |> list.fold_until(acc, f)
// // pub fn fold_until_test() {
// //   let testcase = fn(subject, acc, f) {
// //     subject
// //     |> source.from_list()
// //     |> source.fold_until(acc, f)
// //     |> should.equal(list.fold_until(subject, acc, f))
// //   }

// //   let f = fn(acc, e) {
// //     case e {
// //       _ if e < 6 -> list.Continue([e, ..acc])
// //       _ -> list.Stop(acc)
// //     }
// //   }
// //   testcase([], [], f)
// //   testcase([1], [], f)
// //   testcase([1, 2, 3], [], f)
// //   testcase([1, 2, 3, 4, 5, 6, 7, 8], [], f)

// //   [1, 2, 3, 4, 5, 6, 7, 8]
// //   |> source.from_list()
// //   |> source.fold_until([], f)
// //   |> should.equal([5, 4, 3, 2, 1])
// // }

// // // a |> from_list |> try_fold(acc, f) == a |> list.try_fold(acc, f)
// // pub fn try_fold_test() {
// //   let testcase = fn(subject, acc, fun) {
// //     subject
// //     |> source.from_list()
// //     |> source.try_fold(acc, fun)
// //     |> should.equal(list.try_fold(subject, acc, fun))
// //   }

// //   let f = fn(e, acc) {
// //     case e % 2 {
// //       0 -> Ok(e + acc)
// //       _ -> Error("tried to add an odd number")
// //     }
// //   }
// //   testcase([], 0, f)
// //   testcase([2, 4, 6], 0, f)
// //   testcase([1, 2, 3], 0, f)
// //   testcase([1, 2, 3, 4, 5, 6, 7, 8], 0, f)

// //   [0, 2, 4, 6]
// //   |> source.from_list()
// //   |> source.try_fold(0, f)
// //   |> should.equal(Ok(12))

// //   [1, 2, 3, 4]
// //   |> source.from_list()
// //   |> source.try_fold(0, f)
// //   |> should.equal(Error("tried to add an odd number"))

// //   // TCO test
// //   source.repeat(1)
// //   |> source.take(recursion_test_cycles)
// //   |> source.try_fold(0, fn(e, acc) { Ok(e + acc) })
// // }

// // pub fn first_test() {
// //   source.from_list([1, 2, 3])
// //   |> source.first
// //   |> should.equal(Ok(1))

// //   source.empty()
// //   |> source.first
// //   |> should.equal(Error(Nil))
// // }

// // pub fn at_test() {
// //   source.from_list([1, 2, 3, 4])
// //   |> source.at(2)
// //   |> should.equal(Ok(3))

// //   source.from_list([1, 2, 3, 4])
// //   |> source.at(4)
// //   |> should.equal(Error(Nil))

// //   source.empty()
// //   |> source.at(0)
// //   |> should.equal(Error(Nil))
// // }

// // pub fn length_test() {
// //   source.from_list([1])
// //   |> source.length
// //   |> should.equal(1)

// //   source.from_list([1, 2, 3, 4])
// //   |> source.length
// //   |> should.equal(4)

// //   source.empty()
// //   |> source.length
// //   |> should.equal(0)
// // }

// // pub fn each_test() {
// //   use it <- source.each(source.from_list([1]))
// //   it
// //   |> should.equal(1)
// // }

// // pub fn yield_test() {
// //   let items = {
// //     use <- source.yield(1)
// //     use <- source.yield(2)
// //     use <- source.yield(3)
// //     source.empty()
// //   }

// //   items
// //   |> source.to_list
// //   |> should.equal([1, 2, 3])
// // }

// // pub fn yield_computes_only_necessary_values_test() {
// //   let items = {
// //     use <- source.yield(1)
// //     use <- source.yield(2)
// //     use <- source.yield(3)
// //     source.empty()
// //     panic as "yield computed more values than necessary"
// //   }

// //   items
// //   |> source.take(3)
// //   |> source.to_list
// //   |> should.equal([1, 2, 3])
// // }

// // pub fn prepend_test() {
// //   source.from_list([1, 2, 3])
// //   |> source.prepend(0)
// //   |> source.to_list
// //   |> should.equal([0, 1, 2, 3])
// // }
