import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order

// Internal private representation of a flow
type Action(in, out) {
  // Dedicated to Electric Six
  // https://youtu.be/_30t2dzEgiw?t=162
  Stop
  Continue(out, fn(in) -> Action(in, out))
}

/// A flow is a lazily evaluated sequence of elements.
///
/// Flows are useful when working with collections that are too large to
/// fit in memory (or those that are infinite in size) as they only require the
/// elements currently being processed to be in memory.
///
/// As a lazy data structure no work is done when a flow is filtered,
/// mapped, etc. Instead, a new flow is returned with these transformations
/// applied to the stream. Once the stream has all the required transformations
/// applied it can be evaluated using functions such as `fold` and `to_list`.
///
pub opaque type Flow(in, out) {
  Flow(continuation: fn(in) -> Action(in, out))
}

// Public API for iteration
pub type Step(element, accumulator) {
  Next(element: element, accumulator: accumulator)
  Done
}

// Shortcut for an empty flow.
fn stop() -> Action(in, out) {
  Stop
}
/// Creates a flow from a given function and accumulator.
///
/// The function is called on the accumulator and returns either `Done`,
/// indicating the flow has no more elements, or `Next` which contains a
/// new element and accumulator. The element is yielded by the flow and the
/// new accumulator is used with the function to compute the next element in
/// the sequence.
///
/// ## Examples
///
/// ```gleam
/// unfold(from: 5, with: fn(n) {
///  case n {
///    0 -> Done
///    n -> Next(element: n, accumulator: n - 1)
///  }
/// })
/// |> to_list
/// // -> [5, 4, 3, 2, 1]
/// ```
///
/// Creates a flow that yields values created by calling a given function
/// repeatedly.
///
/// ```gleam
/// repeatedly(fn() { 7 })
/// |> take(3)
/// |> to_list
/// // -> [7, 7, 7]
/// ```
///
// pub fn unfold(
//   from initial: acc,
//   with f: fn(acc) -> Step(element, acc),
// ) -> Flow(in, out) {
//   initial
//   |> unfold_loop(f)
//   |> Flow
// }

// Creating Flows
// fn unfold_loop(
//   initial: acc,
//   f: fn(acc) -> Step(element, acc),
// ) -> fn() -> Action(in, out) {
//   fn() {
//     case f(initial) {
//       Next(x, acc) -> Continue(x, unfold_loop(acc, f))
//       Done -> Stop
//     }
//   }
// }
// pub fn repeatedly(f: fn() -> element) -> Flow(in, out) {
//   unfold(Nil, fn(_) { Next(f(), Nil) })
// }

// /// Creates a flow that returns the same value infinitely.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// repeat(10)
// /// |> take(4)
// /// |> to_list
// /// // -> [10, 10, 10, 10]
// /// ```
// ///
// pub fn repeat(x: element) -> Flow(in, out) {
//   repeatedly(fn() { x })
// }

// /// Creates a flow that yields each element from the given list.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// from_list([1, 2, 3, 4])
// /// |> to_list
// /// // -> [1, 2, 3, 4]
// /// ```
// ///
// pub fn from_list(list: List(element)) -> Flow(in, out) {
//   let yield = fn(acc) {
//     case acc {
//       [] -> Done
//       [head, ..tail] -> Next(head, tail)
//     }
//   }
//   unfold(list, yield)
// }

// // Consuming Flows
// fn transform_loop(
//   continuation: fn(in) -> Action(in, a),
//   state: acc,
//   f: fn(acc, a) -> Step(b, acc),
// ) -> fn() -> Action(in, b) {
//   fn() {
//     case continuation() {
//       Stop -> Stop
//       Continue(el, next) ->
//         case f(state, el) {
//           Done -> Stop
//           Next(yield, next_state) ->
//             Continue(yield, transform_loop(next, next_state, f))
//         }
//     }
//   }
// }

// /// Creates a flow from an existing flow
// /// and a stateful function that may short-circuit.
// ///
// /// `f` takes arguments `acc` for current state and `el` for current element from underlying flow,
// /// and returns either `Next` with yielded element and new state value, or `Done` to halt the flow.
// ///
// /// ## Examples
// ///
// /// Approximate implementation of `index` in terms of `transform`:
// ///
// /// ```gleam
// /// from_list(["a", "b", "c"])
// /// |> transform(0, fn(i, el) { Next(#(i, el), i + 1) })
// /// |> to_list
// /// // -> [#(0, "a"), #(1, "b"), #(2, "c")]
// /// ```
// ///
// pub fn transform(
//   over flow: Flow(in, a),
//   from initial: acc,
//   with f: fn(acc, a) -> Step(b, acc),
// ) -> Flow(in, b) {
//   transform_loop(flow.continuation, initial, f)
//   |> Flow
// }

// /// Reduces a flow of elements into a single value by calling a given
// /// function on each element in turn.
// ///
// /// If called on a flow of infinite length then this function will never
// /// return.
// ///
// /// If you do not care about the end value and only wish to evaluate the
// /// flow for side effects consider using the `run` function instead.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// from_list([1, 2, 3, 4])
// /// |> fold(from: 0, with: fn(acc, element) { element + acc })
// /// // -> 10
// /// ```
// ///
// // pub fn fold(
// //   over flow: Flow(in, e),
// //   from initial: acc,
// //   with f: fn(acc, e) -> acc,
// // ) -> acc {
// //   flow.continuation
// //   |> fold_loop(f, initial)
// // }

// // fn fold_loop(
// //   continuation: fn() -> Action(e),
// //   f: fn(acc, e) -> acc,
// //   accumulator: acc,
// // ) -> acc {
// //   case continuation() {
// //     Continue(elem, next) -> fold_loop(next, f, f(accumulator, elem))
// //     Stop -> accumulator
// //   }
// // }

// // TODO: test
// /// Evaluates all elements emitted by the given flow. This function is useful for when
// /// you wish to trigger any side effects that would occur when evaluating
// /// the flow.
// ///
// pub fn run(flow: Flow(in, out)) -> Nil {
//   fold(flow, Nil, fn(_, _) { Nil })
// }

// /// Evaluates a flow and returns all the elements as a list.
// ///
// /// If called on a flow of infinite length then this function will never
// /// return.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// from_list([1, 2, 3])
// /// |> map(fn(x) { x * 2 })
// /// |> to_list
// /// // -> [2, 4, 6]
// /// ```
// ///
// pub fn to_list(flow: Flow(in, out)) -> List(element) {
//   flow
//   |> fold([], fn(acc, e) { [e, ..acc] })
//   |> list.reverse
// }

// /// Eagerly accesses the first value of a flow, returning a `Next`
// /// that contains the first value and the rest of the flow.
// ///
// /// If called on an empty flow, `Done` is returned.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// let assert Next(first, rest) = from_list([1, 2, 3, 4]) |> step
// ///
// /// first
// /// // -> 1
// ///
// /// rest |> to_list
// /// // -> [2, 3, 4]
// /// ```
// ///
// /// ```gleam
// /// empty() |> step
// /// // -> Done
// /// ```
// ///
// // pub fn step(flow: Flow(e)) -> Step(e, Flow(e)) {
// //   case flow.continuation() {
// //     Stop -> Done
// //     Continue(e, a) -> Next(e, Flow(a))
// //   }
// // }

// /// Creates a flow that only yields the first `desired` elements.
// ///
// /// If the flow does not have enough elements all of them are yielded.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// from_list([1, 2, 3, 4, 5])
// /// |> take(up_to: 3)
// /// |> to_list
// /// // -> [1, 2, 3]
// /// ```
// ///
// /// ```gleam
// /// from_list([1, 2])
// /// |> take(up_to: 3)
// /// |> to_list
// /// // -> [1, 2]
// /// ```
// ///
// pub fn take(from flow: Flow(in, out), up_to desired: Int) -> Flow(in, out) {
//   flow.continuation
//   |> take_loop(desired)
//   |> Flow
// }

// fn take_loop(
//   continuation: fn(in) -> Action(in, out),
//   desired: Int,
// ) -> fn(in) -> Action(in, out) {
//   fn() {
//     case desired > 0 {
//       False -> Stop
//       True ->
//         case continuation() {
//           Stop -> Stop
//           Continue(e, next) -> Continue(e, take_loop(next, desired - 1))
//         }
//     }
//   }
// }

// /// Evaluates and discards the first N elements in a flow, returning a new
// /// flow.
// ///
// /// If the flow does not have enough elements an empty flow is
// /// returned.
// ///
// /// This function does not evaluate the elements of the flow, the
// /// computation is performed when the flow is later run.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// from_list([1, 2, 3, 4, 5])
// /// |> drop(up_to: 3)
// /// |> to_list
// /// // -> [4, 5]
// /// ```
// ///
// /// ```gleam
// /// from_list([1, 2])
// /// |> drop(up_to: 3)
// /// |> to_list
// /// // -> []
// /// ```
// ///
// pub fn drop(from flow: Flow(in, out), up_to desired: Int) -> Flow(in, out) {
//   fn() { drop_loop(flow.continuation, desired) }
//   |> Flow
// }

// fn drop_loop(
//   continuation: fn(in) -> Action(in, out),
//   desired: Int,
// ) -> Action(in, out) {
//   case continuation() {
//     Stop -> Stop
//     Continue(e, next) ->
//       case desired > 0 {
//         True -> drop_loop(next, desired - 1)
//         False -> Continue(e, next)
//       }
//   }
// }

// /// Creates a flow from an existing flow and a transformation function.
// ///
// /// Each element in the new flow will be the result of calling the given
// /// function on the elements in the given flow.
// ///
// /// This function does not evaluate the elements of the flow, the
// /// computation is performed when the flow is later run.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// from_list([1, 2, 3])
// /// |> map(fn(x) { x * 2 })
// /// |> to_list
// /// // -> [2, 4, 6]
// /// ```
// ///
// pub fn map(over flow: Flow(in, a), with f: fn(a) -> b) -> Flow(in, b) {
//   flow.continuation
//   |> map_loop(f)
//   |> Flow
// }

// fn map_loop(
//   continuation: fn(in) -> Action(in, a),
//   f: fn(a) -> b,
// ) -> fn(in) -> Action(in, b) {
//   fn() {
//     case continuation() {
//       Stop -> Stop
//       Continue(e, continuation) -> Continue(f(e), map_loop(continuation, f))
//     }
//   }
// }

// /// Combines two flows into a single one using the given function.
// ///
// /// If a flow is longer than the other the extra elements are dropped.
// ///
// /// This function does not evaluate the elements of the two flows, the
// /// computation is performed when the resulting flow is later run.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// let first = from_list([1, 2, 3])
// /// let second = from_list([4, 5, 6])
// /// map2(first, second, fn(x, y) { x + y }) |> to_list
// /// // -> [5, 7, 9]
// /// ```
// ///
// /// ```gleam
// /// let first = from_list([1, 2])
// /// let second = from_list(["a", "b", "c"])
// /// map2(first, second, fn(i, x) { #(i, x) }) |> to_list
// /// // -> [#(1, "a"), #(2, "b")]
// /// ```
// ///
// pub fn map2(
//   flow1: Flow(in, a),
//   flow2: Flow(in, b),
//   with fun: fn(a, b) -> c,
// ) -> Flow(in, c) {
//   map2_loop(flow1.continuation, flow2.continuation, fun)
//   |> Flow
// }

// fn map2_loop(
//   continuation1: fn(in) -> Action(in, a),
//   continuation2: fn(in) -> Action(in, b),
//   with fun: fn(a, b) -> c,
// ) -> fn(in) -> Action(in, c) {
//   fn(in) {
//     case continuation1(in) {
//       Stop -> Stop
//       Continue(a, next_a) ->
//         case continuation2(in) {
//           Stop -> Stop
//           Continue(b, next_b) ->
//             Continue(fun(a, b), map2_loop(next_a, next_b, fun))
//         }
//     }
//   }
// }

// /// Appends two flows, producing a new flow.
// ///
// /// This function does not evaluate the elements of the flows, the
// /// computation is performed when the resulting flow is later run.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// from_list([1, 2])
// /// |> append(from_list([3, 4]))
// /// |> to_list
// /// // -> [1, 2, 3, 4]
// /// ```
// ///
// pub fn append(
//   to first: Flow(in, out),
//   suffix second: Flow(in, out),
// ) -> Flow(in, out) {
//   fn(in) { append_loop(first.continuation, second.continuation) }
//   |> Flow
// }

// fn append_loop(
//   first: fn(in) -> Action(in, out),
//   second: fn(in) -> Action(in, out),
// ) -> Action(in, out) {
//   case first(in) {
//     Continue(e, first) -> Continue(e, fn(in) { append_loop(first, second) })
//     Stop -> second(in)
//   }
// }

// /// Flattens a flow of flows, creating a new flow.
// ///
// /// This function does not evaluate the elements of the flow, the
// /// computation is performed when the flow is later run.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// from_list([[1, 2], [3, 4]])
// /// |> map(from_list)
// /// |> flatten
// /// |> to_list
// /// // -> [1, 2, 3, 4]
// /// ```
// ///
// pub fn flatten(flow: Flow(in, Flow(in, out))) -> Flow(in, out) {
//   fn() { flatten_loop(flow.continuation) }
//   |> Flow
// }

// fn flatten_loop(
//   flattened: fn(in) -> Action(in, Flow(in, out)),
// ) -> Action(in, out) {
//   case flattened() {
//     Stop -> Stop
//     Continue(it, next_flow) ->
//       append_loop(it.continuation, fn() { flatten_loop(next_flow) })
//   }
// }

// /// Joins a list of flows into a single flow.
// ///
// /// This function does not evaluate the elements of the flow, the
// /// computation is performed when the flow is later run.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// [[1, 2], [3, 4]]
// /// |> map(from_list)
// /// |> concat
// /// |> to_list
// /// // -> [1, 2, 3, 4]
// /// ```
// ///
// pub fn concat(flows: List(Flow(in, out))) -> Flow(in, out) {
//   flatten(from_list(flows))
// }

// /// Creates a flow from an existing flow and a transformation function.
// ///
// /// Each element in the new flow will be the result of calling the given
// /// function on the elements in the given flow and then flattening the
// /// results.
// ///
// /// This function does not evaluate the elements of the flow, the
// /// computation is performed when the flow is later run.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// from_list([1, 2])
// /// |> flat_map(fn(x) { from_list([x, x + 1]) })
// /// |> to_list
// /// // -> [1, 2, 2, 3]
// /// ```
// ///
// pub fn flat_map(
//   over flow: Flow(in, a),
//   with f: fn(a) -> Flow(in, b),
// ) -> Flow(in, b) {
//   flow
//   |> map(f)
//   |> flatten
// }

// /// Creates a flow from an existing flow and a predicate function.
// ///
// /// The new flow will contain elements from the first flow for which
// /// the given function returns `True`.
// ///
// /// This function does not evaluate the elements of the flow, the
// /// computation is performed when the flow is later run.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// import gleam/int
// ///
// /// from_list([1, 2, 3, 4])
// /// |> filter(int.is_even)
// /// |> to_list
// /// // -> [2, 4]
// /// ```
// ///
// pub fn filter(
//   flow: Flow(in, a),
//   keeping predicate: fn(a) -> Bool,
// ) -> Flow(in, a) {
//   fn(in) { filter_loop(flow.continuation, predicate) }
//   |> Flow
// }

// fn filter_loop(
//   continuation: fn(in) -> Action(in, out),
//   predicate: fn(out) -> Bool,
// ) -> Action(in, out) {
//   case continuation() {
//     Stop -> Stop
//     Continue(e, flow) ->
//       case predicate(e) {
//         True -> Continue(e, fn() { filter_loop(flow, predicate) })
//         False -> filter_loop(flow, predicate)
//       }
//   }
// }

// /// Creates a flow from an existing flow and a transforming predicate function.
// ///
// /// The new flow will contain elements from the first flow for which
// /// the given function returns `Ok`, transformed to the value inside the `Ok`.
// ///
// /// This function does not evaluate the elements of the flow, the
// /// computation is performed when the flow is later run.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// import gleam/string
// /// import gleam/int
// ///
// /// "a1b2c3d4e5f"
// /// |> string.to_graphemes
// /// |> from_list
// /// |> filter_map(int.parse)
// /// |> to_list
// /// // -> [1, 2, 3, 4, 5]
// /// ```
// ///
// pub fn filter_map(
//   flow: Flow(in, a),
//   keeping_with f: fn(a) -> Result(b, c),
// ) -> Flow(in, b) {
//   fn(in) { filter_map_loop(flow.continuation, f) }
//   |> Flow
// }

// fn filter_map_loop(
//   continuation: fn(in) -> Action(in, a),
//   f: fn(a) -> Result(b, c),
// ) -> Action(in, b) {
//   case continuation() {
//     Stop -> Stop
//     Continue(e, next) ->
//       case f(e) {
//         Ok(e) -> Continue(e, fn() { filter_map_loop(next, f) })
//         Error(_) -> filter_map_loop(next, f)
//       }
//   }
// }

// /// Wraps values yielded from a flow with indices, starting from 0.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// from_list(["a", "b", "c"]) |> index |> to_list
// /// // -> [#("a", 0), #("b", 1), #("c", 2)]
// /// ```
// ///
// pub fn index(over flow: Flow(in, out)) -> Flow(in, #(element, Int)) {
//   flow.continuation
//   |> index_loop(0)
//   |> Flow
// }

// fn index_loop(
//   continuation: fn(in) -> Action(in, out),
//   next: Int,
// ) -> fn(in) -> Action(in, #(element, Int)) {
//   fn(in) {
//     case continuation() {
//       Stop -> Stop
//       Continue(e, continuation) ->
//         Continue(#(e, next), index_loop(continuation, next + 1))
//     }
//   }
// }

// /// Creates a flow that infinitely applies a function to a value.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// iterate(1, fn(n) { n * 3 }) |> take(5) |> to_list
// /// // -> [1, 3, 9, 27, 81]
// /// ```
// ///
// pub fn iterate(from initial: out, with f: fn(out) -> out) -> Flow(in, out) {
//   unfold(initial, fn(element) { Next(element, f(element)) })
// }

// /// Creates a flow that yields elements while the predicate returns `True`.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// from_list([1, 2, 3, 2, 4])
// /// |> take_while(satisfying: fn(x) { x < 3 })
// /// |> to_list
// /// // -> [1, 2]
// /// ```
// ///
// pub fn take_while(
//   in flow: Flow(in, out),
//   satisfying predicate: fn(out) -> Bool,
// ) -> Flow(in, out) {
//   flow.continuation
//   |> take_while_loop(predicate)
//   |> Flow
// }

// fn take_while_loop(
//   continuation: fn(in) -> Action(in, out),
//   predicate: fn(in) -> Bool,
// ) -> fn(in) -> Action(in, out) {
//   fn(in) {
//     case continuation() {
//       Stop -> Stop
//       Continue(e, next) ->
//         case predicate(e) {
//           False -> Stop
//           True -> Continue(e, take_while_loop(next, predicate))
//         }
//     }
//   }
// }

// /// Creates a flow that drops elements while the predicate returns `True`,
// /// and then yields the remaining elements.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// from_list([1, 2, 3, 4, 2, 5])
// /// |> drop_while(satisfying: fn(x) { x < 4 })
// /// |> to_list
// /// // -> [4, 2, 5]
// /// ```
// ///
// pub fn drop_while(
//   in flow: Flow(in, out),
//   satisfying predicate: fn(out) -> Bool,
// ) -> Flow(in, out) {
//   fn(in) { drop_while_loop(flow.continuation, predicate) }
//   |> Flow
// }

// fn drop_while_loop(
//   continuation: fn(in) -> Action(in, out),
//   predicate: fn(out) -> Bool,
// ) -> Action(in, out) {
//   case continuation() {
//     Stop -> Stop
//     Continue(e, next) ->
//       case predicate(e) {
//         False -> Continue(e, next)
//         True -> drop_while_loop(next, predicate)
//       }
//   }
// }

// /// Creates a flow from an existing flow and a stateful function.
// ///
// /// Specifically, this behaves like `fold`, but yields intermediate results.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// // Generate a sequence of partial sums
// /// from_list([1, 2, 3, 4, 5])
// /// |> scan(from: 0, with: fn(acc, el) { acc + el })
// /// |> to_list
// /// // -> [1, 3, 6, 10, 15]
// /// ```
// ///
// pub fn scan(
//   over flow: Flow(in, out),
//   from initial: acc,
//   with f: fn(acc, out) -> acc,
// ) -> Flow(in, acc) {
//   flow.continuation
//   |> scan_loop(f, initial)
//   |> Flow
// }

// fn scan_loop(
//   continuation: fn(in) -> Action(in, out),
//   f: fn(acc, out) -> acc,
//   accumulator: acc,
// ) -> fn(in) -> Action(in, acc) {
//   fn(in) {
//     case continuation() {
//       Stop -> Stop
//       Continue(el, next) -> {
//         let accumulated = f(accumulator, el)
//         Continue(accumulated, scan_loop(next, f, accumulated))
//       }
//     }
//   }
// }

// /// Zips two flows together, emitting values from both
// /// until the shorter one runs out.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// from_list(["a", "b", "c"])
// /// |> zip(range(20, 30))
// /// |> to_list
// /// // -> [#("a", 20), #("b", 21), #("c", 22)]
// /// ```
// ///
// pub fn zip(left: Flow(in, a), right: Flow(in, b)) -> Flow(in, #(a, b)) {
//   zip_loop(left.continuation, right.continuation)
//   |> Flow
// }

// fn zip_loop(
//   left: fn(in) -> Action(in, a),
//   right: fn(in) -> Action(in, b),
// ) -> fn(in) -> Action(in, #(a, b)) {
//   fn(in) {
//     case left() {
//       Stop -> Stop
//       Continue(el_left, next_left) ->
//         case right() {
//           Stop -> Stop
//           Continue(el_right, next_right) ->
//             Continue(#(el_left, el_right), zip_loop(next_left, next_right))
//         }
//     }
//   }
// }

// // Result of collecting a single chunk by key
// type Chunk(element, key) {
//   AnotherBy(List(element), key, element, fn() -> Action(in, out))
//   LastBy(List(element))
// }

// /// Creates a flow that emits chunks of elements
// /// for which `f` returns the same value.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// from_list([1, 2, 2, 3, 4, 4, 6, 7, 7])
// /// |> chunk(by: fn(n) { n % 2 })
// /// |> to_list
// /// // -> [[1], [2, 2], [3], [4, 4, 6], [7, 7]]
// /// ```
// ///
// pub fn chunk(
//   over flow: Flow(in, out),
//   by f: fn(element) -> key,
// ) -> Flow(in, List(element)) {
//   fn(in) {
//     case flow.continuation() {
//       Stop -> Stop
//       Continue(e, next) -> chunk_loop(next, f, f(e), e)
//     }
//   }
//   |> Flow
// }

// fn chunk_loop(
//   continuation: fn(in) -> Action(in, out),
//   f: fn(out) -> key,
//   previous_key: key,
//   previous_element: out,
// ) -> Action(in, List(out)) {
//   case next_chunk(continuation, f, previous_key, [previous_element]) {
//     LastBy(chunk) -> Continue(chunk, stop)
//     AnotherBy(chunk, key, el, next) ->
//       Continue(chunk, fn() { chunk_loop(next, f, key, el) })
//   }
// }

// fn next_chunk(
//   continuation: fn(in) -> Action(in, out),
//   f: fn(out) -> key,
//   previous_key: key,
//   current_chunk: List(out),
// ) -> Chunk(out, key) {
//   case continuation() {
//     Stop -> LastBy(list.reverse(current_chunk))
//     Continue(e, next) -> {
//       let key = f(e)
//       case key == previous_key {
//         True -> next_chunk(next, f, key, [e, ..current_chunk])
//         False -> AnotherBy(list.reverse(current_chunk), key, e, next)
//       }
//     }
//   }
// }

// /// Creates a flow that emits chunks of given size.
// ///
// /// If the last chunk does not have `count` elements, it is yielded
// /// as a partial chunk, with less than `count` elements.
// ///
// /// For any `count` less than 1 this function behaves as if it was set to 1.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// from_list([1, 2, 3, 4, 5, 6])
// /// |> sized_chunk(into: 2)
// /// |> to_list
// /// // -> [[1, 2], [3, 4], [5, 6]]
// /// ```
// ///
// /// ```gleam
// /// from_list([1, 2, 3, 4, 5, 6, 7, 8])
// /// |> sized_chunk(into: 3)
// /// |> to_list
// /// // -> [[1, 2, 3], [4, 5, 6], [7, 8]]
// /// ```
// ///
// pub fn sized_chunk(
//   over flow: Flow(in, out),
//   into count: Int,
// ) -> Flow(in, List(out)) {
//   flow.continuation
//   |> sized_chunk_loop(count)
//   |> Flow
// }

// fn sized_chunk_loop(
//   continuation: fn(in) -> Action(in, out),
//   count: Int,
// ) -> fn(in) -> Action(in, List(out)) {
//   fn(in) {
//     case next_sized_chunk(continuation, count, []) {
//       NoMore -> Stop
//       Last(chunk) -> Continue(chunk, stop)
//       Another(chunk, next_element) ->
//         Continue(chunk, sized_chunk_loop(next_element, count))
//     }
//   }
// }

// // Result of collecting a single sized chunk
// type SizedChunk(in, out) {
//   Another(List(out), fn(in) -> Action(in, out))
//   Last(List(out))
//   NoMore
// }

// fn next_sized_chunk(
//   continuation: fn(in) -> Action(in, out),
//   left: Int,
//   current_chunk: List(out),
// ) -> SizedChunk(in, out) {
//   case continuation() {
//     Stop ->
//       case current_chunk {
//         [] -> NoMore
//         remaining -> Last(list.reverse(remaining))
//       }
//     Continue(e, next) -> {
//       let chunk = [e, ..current_chunk]
//       case left > 1 {
//         False -> Another(list.reverse(chunk), next)
//         True -> next_sized_chunk(next, left - 1, chunk)
//       }
//     }
//   }
// }

// /// Creates a flow that yields the given `elem` element
// /// between elements emitted by the underlying flow.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// empty()
// /// |> intersperse(with: 0)
// /// |> to_list
// /// // -> []
// /// ```
// ///
// /// ```gleam
// /// from_list([1])
// /// |> intersperse(with: 0)
// /// |> to_list
// /// // -> [1]
// /// ```
// ///
// /// ```gleam
// /// from_list([1, 2, 3, 4, 5])
// /// |> intersperse(with: 0)
// /// |> to_list
// /// // -> [1, 0, 2, 0, 3, 0, 4, 0, 5]
// /// ```
// ///
// pub fn intersperse(over flow: Flow(in, out), with elem: out) -> Flow(in, out) {
//   fn(in) {
//     case flow.continuation() {
//       Stop -> Stop
//       Continue(e, next) -> Continue(e, fn() { intersperse_loop(next, elem) })
//     }
//   }
//   |> Flow
// }

// fn intersperse_loop(
//   continuation: fn(in) -> Action(in, out),
//   separator: out,
// ) -> Action(in, out) {
//   case continuation() {
//     Stop -> Stop
//     Continue(e, next) -> {
//       let next_interspersed = fn() { intersperse_loop(next, separator) }
//       Continue(separator, fn() { Continue(e, next_interspersed) })
//     }
//   }
// }

// /// Returns `True` if any element emitted by the flow satisfies the given predicate,
// /// `False` otherwise.
// ///
// /// This function short-circuits once it finds a satisfying element.
// ///
// /// An empty flow results in `False`.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// empty()
// /// |> any(fn(n) { n % 2 == 0 })
// /// // -> False
// /// ```
// ///
// /// ```gleam
// /// from_list([1, 2, 5, 7, 9])
// /// |> any(fn(n) { n % 2 == 0 })
// /// // -> True
// /// ```
// ///
// /// ```gleam
// /// from_list([1, 3, 5, 7, 9])
// /// |> any(fn(n) { n % 2 == 0 })
// /// // -> False
// /// ```
// ///
// // pub fn any(
// //   in flow: Flow(in, out),
// //   satisfying predicate: fn(element) -> Bool,
// // ) -> Bool {
// //   flow.continuation
// //   |> any_loop(predicate)
// // }

// // fn any_loop(
// //   continuation: fn() -> Action(in, out),
// //   predicate: fn(element) -> Bool,
// // ) -> Bool {
// //   case continuation() {
// //     Stop -> False
// //     Continue(e, next) ->
// //       case predicate(e) {
// //         True -> True
// //         False -> any_loop(next, predicate)
// //       }
// //   }
// // }

// /// Returns `True` if all elements emitted by the flow satisfy the given predicate,
// /// `False` otherwise.
// ///
// /// This function short-circuits once it finds a non-satisfying element.
// ///
// /// An empty flow results in `True`.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// empty()
// /// |> all(fn(n) { n % 2 == 0 })
// /// // -> True
// /// ```
// ///
// /// ```gleam
// /// from_list([2, 4, 6, 8])
// /// |> all(fn(n) { n % 2 == 0 })
// /// // -> True
// /// ```
// ///
// /// ```gleam
// /// from_list([2, 4, 5, 8])
// /// |> all(fn(n) { n % 2 == 0 })
// /// // -> False
// /// ```
// ///
// // pub fn all(
// //   in flow: Flow(in, out),
// //   satisfying predicate: fn(element) -> Bool,
// // ) -> Bool {
// //   flow.continuation
// //   |> all_loop(predicate)
// // }

// // fn all_loop(
// //   continuation: fn() -> Action(in, out),
// //   predicate: fn(element) -> Bool,
// // ) -> Bool {
// //   case continuation() {
// //     Stop -> True
// //     Continue(e, next) ->
// //       case predicate(e) {
// //         True -> all_loop(next, predicate)
// //         False -> False
// //       }
// //   }
// // }

// /// Returns a `Dict(k, List(element))` of elements from the given flow
// /// grouped with the given key function.
// ///
// /// The order within each group is preserved from the flow.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// from_list([1, 2, 3, 4, 5, 6])
// /// |> group(by: fn(n) { n % 3 })
// /// // -> dict.from_list([#(0, [3, 6]), #(1, [1, 4]), #(2, [2, 5])])
// /// ```
// ///
// // pub fn group(
// //   in flow: Flow(in, out),
// //   by key: fn(element) -> key,
// // ) -> Dict(key, List(element)) {
// //   flow
// //   |> fold(dict.new(), group_updater(key))
// //   |> dict.map_values(fn(_, group) { list.reverse(group) })
// // }

// // fn group_updater(
// //   f: fn(element) -> key,
// // ) -> fn(Dict(key, List(element)), element) -> Dict(key, List(element)) {
// //   fn(groups, elem) {
// //     groups
// //     |> dict.upsert(f(elem), update_group_with(elem))
// //   }
// // }

// // fn update_group_with(el: element) -> fn(Option(List(element))) -> List(element) {
// //   fn(maybe_group) {
// //     case maybe_group {
// //       Some(group) -> [el, ..group]
// //       None -> [el]
// //     }
// //   }
// // }

// /// This function acts similar to fold, but does not take an initial state.
// /// Instead, it starts from the first yielded element
// /// and combines it with each subsequent element in turn using the given function.
// /// The function is called as `f(accumulator, current_element)`.
// ///
// /// Returns `Ok` to indicate a successful run, and `Error` if called on an empty flow.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// from_list([])
// /// |> reduce(fn(acc, x) { acc + x })
// /// // -> Error(Nil)
// /// ```
// ///
// /// ```gleam
// /// from_list([1, 2, 3, 4, 5])
// /// |> reduce(fn(acc, x) { acc + x })
// /// // -> Ok(15)
// /// ```
// ///
// // pub fn reduce(over flow: Flow(in, e), with f: fn(e, e) -> e) -> Result(e, Nil) {
// //   case flow.continuation() {
// //     Stop -> Error(Nil)
// //     Continue(e, next) ->
// //       fold_loop(next, f, e)
// //       |> Ok
// //   }
// // }

// /// Returns the last element in the given flow.
// ///
// /// Returns `Error(Nil)` if the flow is empty.
// ///
// /// This function runs in linear time.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// empty() |> last
// /// // -> Error(Nil)
// /// ```
// ///
// /// ```gleam
// /// range(1, 10) |> last
// /// // -> Ok(10)
// /// ```
// ///
// // pub fn last(flow: Flow(in, out)) -> Result(element, Nil) {
// //   flow
// //   |> reduce(fn(_, elem) { elem })
// // }

// /// Creates a flow that yields no elements.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// empty() |> to_list
// /// // -> []
// /// ```
// ///
// pub fn empty() -> Flow(in, out) {
//   Flow(stop)
// }

// /// Creates a flow that yields exactly one element provided by calling the given function.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// once(fn() { 1 }) |> to_list
// /// // -> [1]
// /// ```
// ///
// pub fn once(f: fn(in) -> element) -> Flow(in, out) {
//   fn(in) { Continue(f(), stop) }
//   |> Flow
// }

// /// Creates a flow that yields the given element exactly once.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// single(1) |> to_list
// /// // -> [1]
// /// ```
// ///
// pub fn single(elem: out) -> Flow(in, out) {
//   once(fn(in) { elem })
// }

// /// Creates a flow that alternates between the two given flows
// /// until both have run out.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// from_list([1, 2, 3, 4])
// /// |> interleave(from_list([11, 12, 13, 14]))
// /// |> to_list
// /// // -> [1, 11, 2, 12, 3, 13, 4, 14]
// /// ```
// ///
// /// ```gleam
// /// from_list([1, 2, 3, 4])
// /// |> interleave(from_list([100]))
// /// |> to_list
// /// // -> [1, 100, 2, 3, 4]
// /// ```
// ///
// pub fn interleave(
//   left: Flow(in, out),
//   with right: Flow(in, out),
// ) -> Flow(in, out) {
//   fn(in) { interleave_loop(left.continuation, right.continuation) }
//   |> Flow
// }

// fn interleave_loop(
//   current: fn(in) -> Action(in, out),
//   next: fn(in) -> Action(in, out),
// ) -> Action(in, out) {
//   case current() {
//     Stop -> next()
//     Continue(e, next_other) ->
//       Continue(e, fn(in) { interleave_loop(next, next_other) })
//   }
// }

// /// Like `fold`, `fold_until` reduces a flow of elements into a single value by calling a given
// /// function on each element in turn, but uses `list.ContinueOrStop` to determine
// /// whether or not to keep iterating.
// ///
// /// If called on a flow of infinite length then this function will only ever
// /// return if the function returns `list.Stop`.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// import gleam/list
// ///
// /// let f = fn(acc, e) {
// ///   case e {
// ///     _ if e < 4 -> list.Continue(e + acc)
// ///     _ -> list.Stop(acc)
// ///   }
// /// }
// ///
// /// from_list([1, 2, 3, 4])
// /// |> fold_until(from: 0, with: f)
// /// // -> 6
// /// ```
// ///
// // pub fn fold_until(
// //   over flow: Flow(in, e),
// //   from initial: acc,
// //   with f: fn(acc, e) -> list.ContinueOrStop(acc),
// // ) -> acc {
// //   flow.continuation
// //   |> fold_until_loop(f, initial)
// // }

// // fn fold_until_loop(
// //   continuation: fn() -> Action(e),
// //   f: fn(acc, e) -> list.ContinueOrStop(acc),
// //   accumulator: acc,
// // ) -> acc {
// //   case continuation() {
// //     Stop -> accumulator
// //     Continue(elem, next) ->
// //       case f(accumulator, elem) {
// //         list.Continue(accumulator) -> fold_until_loop(next, f, accumulator)
// //         list.Stop(accumulator) -> accumulator
// //       }
// //   }
// // }

// /// A variant of fold that might fail.
// ///
// /// The folding function should return `Result(accumulator, error)`.
// /// If the returned value is `Ok(accumulator)` try_fold will try the next value in the flow.
// /// If the returned value is `Error(error)` try_fold will stop and return that error.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// from_list([1, 2, 3, 4])
// /// |> try_fold(0, fn(acc, i) {
// ///   case i < 3 {
// ///     True -> Ok(acc + i)
// ///     False -> Error(Nil)
// ///   }
// /// })
// /// // -> Error(Nil)
// /// ```
// ///
// // pub fn try_fold(
// //   over flow: Flow(e),
// //   from initial: acc,
// //   with f: fn(acc, e) -> Result(acc, err),
// // ) -> Result(acc, err) {
// //   flow.continuation
// //   |> try_fold_loop(f, initial)
// // }

// // fn try_fold_loop(
// //   over continuation: fn() -> Action(a),
// //   with f: fn(acc, a) -> Result(acc, err),
// //   from accumulator: acc,
// // ) -> Result(acc, err) {
// //   case continuation() {
// //     Stop -> Ok(accumulator)
// //     Continue(elem, next) -> {
// //       case f(accumulator, elem) {
// //         Ok(result) -> try_fold_loop(next, f, result)
// //         Error(_) as error -> error
// //       }
// //     }
// //   }
// // }

// /// Returns the first element yielded by the given flow, if it exists,
// /// or `Error(Nil)` otherwise.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// from_list([1, 2, 3]) |> first
// /// // -> Ok(1)
// /// ```
// ///
// /// ```gleam
// /// empty() |> first
// /// // -> Error(Nil)
// /// ```
// // pub fn first(from flow: Flow(e)) -> Result(e, Nil) {
// //   case flow.continuation() {
// //     Stop -> Error(Nil)
// //     Continue(e, _) -> Ok(e)
// //   }
// // }

// /// Returns nth element yielded by the given flow, where `0` means the first element.
// ///
// /// If there are not enough elements in the flow, `Error(Nil)` is returned.
// ///
// /// For any `index` less than `0` this function behaves as if it was set to `0`.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// from_list([1, 2, 3, 4]) |> at(2)
// /// // -> Ok(3)
// /// ```
// ///
// /// ```gleam
// /// from_list([1, 2, 3, 4]) |> at(4)
// /// // -> Error(Nil)
// /// ```
// ///
// /// ```gleam
// /// empty() |> at(0)
// /// // -> Error(Nil)
// /// ```
// ///
// // pub fn at(in flow: Flow(e), get index: Int) -> Result(e, Nil) {
// //   flow
// //   |> drop(index)
// //   |> first
// // }

// /// Counts the number of elements in the given flow.
// ///
// /// This function has to traverse the entire flow to count its elements,
// /// so it runs in linear time.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// empty() |> length
// /// // -> 0
// /// ```
// ///
// /// ```gleam
// /// from_list([1, 2, 3, 4]) |> length
// /// // -> 4
// /// ```
// ///
// // pub fn length(over flow: Flow(e)) -> Int {
// //   flow.continuation
// //   |> length_loop(0)
// // }

// // fn length_loop(over continuation: fn() -> Action(e), with length: Int) -> Int {
// //   case continuation() {
// //     Stop -> length
// //     Continue(_, next) -> length_loop(next, length + 1)
// //   }
// // }

// /// Traverse a flow, calling a function on each element.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// empty() |> each(io.println)
// /// // -> Nil
// /// ```
// ///
// /// ```gleam
// /// from_list(["Tom", "Malory", "Louis"]) |> each(io.println)
// /// // -> Nil
// /// // Tom
// /// // Malory
// /// // Louis
// /// ```
// ///
// // pub fn each(over flow: Flow(a), with f: fn(a) -> b) -> Nil {
// //   flow
// //   |> map(f)
// //   |> run
// // }

// /// Add a new element to the start of a flow.
// ///
// /// This function is for use with `use` expressions, to replicate the behaviour
// /// of the `yield` keyword found in other languages.
// ///
// /// If you only need to prepend an element and don't require the `use` syntax,
// /// use `prepend`.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// let flow = {
// ///   use <- yield(1)
// ///   use <- yield(2)
// ///   use <- yield(3)
// ///   empty()
// /// }
// ///
// /// flow |> to_list
// /// // -> [1, 2, 3]
// /// ```
// ///
// pub fn yield(element: a, next: fn(in) -> Flow(in, a)) -> Flow(in, a) {
//   Flow(fn(in) { Continue(element, fn(in) { next(in).continuation() }) })
// }

// /// Add a new element to the start of a flow.
// ///
// /// ## Examples
// ///
// /// ```gleam
// /// let flow = from_list([1, 2, 3]) |> prepend(0)
// ///
// /// flow.to_list
// /// // -> [0, 1, 2, 3]
// /// ```
// ///
// pub fn prepend(flow: Flow(in, a), element: a) -> Flow(in, a) {
//   use <- yield(element)
//   flow
// }
