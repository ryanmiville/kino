import gleam/bool
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/order
import gleam/otp/actor.{type StartError}
import gleam/result
import kino/stream/internal/action.{type Action, Continue, Emit, Stop}
import kino/stream/internal/flatten
import kino/stream/internal/flow
import kino/stream/internal/interleave
import kino/stream/internal/intersperse
import kino/stream/internal/sink
import kino/stream/internal/source
import kino/stream/internal/try_fold
import kino/stream/internal/zip

type Stage(element) =
  Result(Subject(source.Pull(element)), StartError)

pub opaque type Stream(element) {
  Source(continuation: fn(Dynamic) -> Action(Dynamic, element))
  Flow(
    source: fn() -> Stage(Dynamic),
    continuation: fn(Dynamic) -> Action(Dynamic, element),
  )
}

pub type Step(element, state) {
  Next(element: element, state: state)
  Done
}

// Shortcut for an empty stream.
fn stop(_in: in) -> Action(in, out) {
  Stop
}

// Shortcut for a flow that does nothing to the input.
fn identity() -> fn(in) -> Action(in, in) {
  do_unfold(Nil, fn(acc, a) { Next(a, acc) })
}

pub fn unfold(
  from initial: acc,
  with f: fn(acc) -> Step(element, acc),
) -> Stream(element) {
  let step = fn(acc, _in) { f(acc) }
  initial
  |> do_unfold(step)
  |> Source
}

fn do_unfold(
  initial: acc,
  f: fn(acc, in) -> Step(out, acc),
) -> fn(in) -> Action(in, out) {
  fn(in) {
    case f(initial, in) {
      Next(x, acc) -> Emit(x, do_unfold(acc, f))
      Done -> Stop
    }
  }
}

pub fn repeatedly(f: fn() -> element) -> Stream(element) {
  unfold(Nil, fn(_) { Next(f(), Nil) })
}

pub fn repeat(x: element) -> Stream(element) {
  repeatedly(fn() { x })
}

pub fn from_list(elements: List(element)) -> Stream(element) {
  let f = fn(state) {
    case state {
      [] -> Done
      [head, ..tail] -> Next(head, tail)
    }
  }
  unfold(elements, f)
}

pub fn single(element: element) -> Stream(element) {
  once(fn() { element })
}

pub fn map(stream: Stream(a), f: fn(a) -> b) -> Stream(b) {
  case stream {
    Source(cont) -> Source(do_map(cont, f))
    Flow(source, cont) -> Flow(source, do_map(cont, f))
  }
}

fn do_map(
  continuation: fn(in) -> Action(in, a),
  f: fn(a) -> b,
) -> fn(in) -> Action(in, b) {
  fn(in) {
    case continuation(in) {
      Stop -> Stop
      Continue(next) -> Continue(do_map(next, f))
      Emit(e, continuation) -> Emit(f(e), do_map(continuation, f))
    }
  }
}

pub fn async(stream: Stream(a)) -> Stream(a) {
  case stream {
    Source(_) ->
      Flow(fn() { start(stream) |> unsafe_coerce }, unsafe_coerce(identity()))
    Flow(source, flow) -> {
      let new_source = fn() { start_with_flow(source(), flow) }
      Flow(unsafe_coerce(new_source), unsafe_coerce(identity()))
    }
  }
}

fn start_with_flow(
  source: Stage(Dynamic),
  flow: fn(Dynamic) -> Action(Dynamic, element),
) -> Stage(element) {
  use source <- result.try(source)
  flow.start([source], flow)
}

pub fn empty() -> Stream(element) {
  Source(stop)
}

pub fn take(stream: Stream(element), desired: Int) -> Stream(element) {
  use <- bool.lazy_guard(desired <= 0, empty)
  case stream {
    Source(cont) -> Source(do_take(cont, desired))
    Flow(source, flow) -> Flow(source, do_take(flow, desired))
  }
}

fn do_take(
  continuation: fn(in) -> Action(in, out),
  desired: Int,
) -> fn(in) -> Action(in, out) {
  fn(in) {
    case desired > 0 {
      False -> Stop
      True ->
        case continuation(in) {
          Stop -> Stop
          Continue(next) -> Continue(do_take(next, desired - 1))
          Emit(e, next) -> Emit(e, do_take(next, desired - 1))
        }
    }
  }
}

pub fn filter(stream: Stream(a), keeping predicate: fn(a) -> Bool) -> Stream(a) {
  case stream {
    Source(cont) -> Source(do_filter(cont, predicate))
    Flow(source, cont) -> Flow(source, do_filter(cont, predicate))
  }
}

fn do_filter(
  continuation: fn(in) -> Action(in, out),
  predicate: fn(out) -> Bool,
) -> fn(in) -> Action(in, out) {
  fn(in) {
    case continuation(in) {
      Stop -> Stop
      Continue(next) -> Continue(do_filter(next, predicate))
      Emit(e, stream) ->
        case predicate(e) {
          True -> Emit(e, do_filter(stream, predicate))
          False -> Continue(do_filter(stream, predicate))
        }
    }
  }
}

pub fn fold(
  stream: Stream(element),
  from initial: acc,
  with f: fn(acc, element) -> acc,
) -> Result(acc, StartError) {
  use source <- result.try(start(stream))
  use sub <- result.map(sink.start(source, initial, f))
  process.receive_forever(sub)
}

pub fn to_list(stream: Stream(element)) -> Result(List(element), StartError) {
  let f = fn(acc, x) { [x, ..acc] }
  fold(stream, [], f) |> result.map(list.reverse)
}

fn start(stream: Stream(element)) -> Stage(element) {
  case stream {
    Source(continuation) -> source.start(unsafe_coerce(continuation))
    Flow(source, flow) -> start_with_flow(source(), flow)
  }
}

pub fn append(to first: Stream(a), suffix second: Stream(a)) -> Stream(a) {
  case first, second {
    Source(c1), Source(c2) -> Source(append_continuation(c1, c2))

    Source(c1), Flow(s2, c2) -> {
      let source =
        fn() {
          let s1 = source.start(unsafe_coerce(c1))
          use s2 <- result.try(s2())
          let s2 = flow.start([s2], c2)
          merge_stages(s1, s2)
        }
        |> unsafe_coerce
      Flow(source, unsafe_coerce(identity()))
    }

    Flow(s1, c1), Source(c2) -> {
      let source = fn() {
        use s1 <- result.try(s1())
        let s1 = flow.start([s1], c1) |> unsafe_coerce
        let s2 = source.start(unsafe_coerce(c2))
        merge_stages(s1, s2)
      }
      Flow(source, unsafe_coerce(identity()))
    }

    Flow(s1, c1), Flow(s2, c2) -> {
      let source =
        fn() {
          use s1 <- result.try(s1())
          let s1 = flow.start([s1], c1)
          use s2 <- result.try(s2())
          let s2 = flow.start([s2], c2)
          merge_stages(s1, s2)
        }
        |> unsafe_coerce
      Flow(source, unsafe_coerce(identity()))
    }
  }
}

fn append_continuation(
  first: fn(in) -> Action(in, a),
  second: fn(in) -> Action(in, a),
) -> fn(in) -> Action(in, a) {
  fn(in) {
    case first(in) {
      Emit(a, next) -> Emit(a, append_continuation(next, second))
      Continue(next) -> Continue(append_continuation(next, second))
      Stop -> second(in)
    }
  }
}

fn merge_stages(first: Stage(a), second: Stage(a)) -> Stage(a) {
  use first <- result.try(first)
  use second <- result.try(second)
  flow.start([first, second], identity())
}

pub fn flatten(stream: Stream(Stream(a))) -> Stream(a) {
  let source =
    fn() {
      let stream = map(stream, fn(s) { fn() { start(s) } })
      use stream_source <- result.try(start(stream))
      flatten.start(stream_source)
    }
    |> unsafe_coerce
  Flow(source, unsafe_coerce(identity()))
}

pub fn flat_map(over stream: Stream(a), with f: fn(a) -> Stream(b)) -> Stream(b) {
  stream
  |> map(f)
  |> flatten
}

pub fn filter_map(
  stream: Stream(a),
  keeping_with f: fn(a) -> Result(b, c),
) -> Stream(b) {
  case stream {
    Source(cont) -> Source(do_filter_map(cont, f))
    Flow(source, cont) -> Flow(source, do_filter_map(cont, f))
  }
}

fn do_filter_map(
  continuation: fn(in) -> Action(in, a),
  f: fn(a) -> Result(b, c),
) -> fn(in) -> Action(in, b) {
  fn(in) {
    case continuation(in) {
      Stop -> Stop
      Continue(next) -> Continue(do_filter_map(next, f))
      Emit(e, next) ->
        case f(e) {
          Ok(e) -> Emit(e, do_filter_map(next, f))
          Error(_) -> Continue(do_filter_map(next, f))
        }
    }
  }
}

pub fn transform(
  over stream: Stream(a),
  from initial: acc,
  with f: fn(acc, a) -> Step(b, acc),
) -> Stream(b) {
  case stream {
    Source(cont) -> Source(transform_loop(cont, initial, f))
    Flow(source, cont) -> Flow(source, transform_loop(cont, initial, f))
  }
}

fn transform_loop(
  continuation: fn(in) -> Action(in, a),
  state: acc,
  f: fn(acc, a) -> Step(b, acc),
) -> fn(in) -> Action(in, b) {
  fn(in) {
    case continuation(in) {
      Stop -> Stop
      Continue(next) -> Continue(transform_loop(next, state, f))
      Emit(el, next) ->
        case f(state, el) {
          Done -> Stop
          Next(yield, next_state) ->
            Emit(yield, transform_loop(next, next_state, f))
        }
    }
  }
}

pub fn range(from start: Int, to stop: Int) -> Stream(Int) {
  case int.compare(start, stop) {
    order.Eq -> once(fn() { start })
    order.Gt ->
      unfold(from: start, with: fn(current) {
        case current < stop {
          False -> Next(current, current - 1)
          True -> Done
        }
      })

    order.Lt ->
      unfold(from: start, with: fn(current) {
        case current > stop {
          False -> Next(current, current + 1)
          True -> Done
        }
      })
  }
}

pub fn index(over stream: Stream(element)) -> Stream(#(element, Int)) {
  let f = fn(state, el) { Next(#(el, state), state + 1) }
  stream
  |> transform(0, f)
}

pub fn drop(from stream: Stream(element), up_to desired: Int) -> Stream(element) {
  case stream {
    Source(cont) -> Source(do_drop(cont, desired))
    Flow(source, cont) -> Flow(source, do_drop(cont, desired))
  }
}

fn do_drop(
  continuation: fn(in) -> Action(in, out),
  desired: Int,
) -> fn(in) -> Action(in, out) {
  fn(in) {
    case continuation(in) {
      Stop -> Stop
      Emit(e, next) ->
        case desired > 0 {
          True -> Continue(do_drop(next, desired - 1))
          False -> Emit(e, next)
        }
      Continue(next) ->
        case desired > 0 {
          True -> Continue(do_drop(next, desired - 1))
          False -> Continue(next)
        }
    }
  }
}

pub fn concat(from streams: List(Stream(element))) -> Stream(element) {
  flatten(from_list(streams))
}

pub fn iterate(
  from initial: element,
  with f: fn(element) -> element,
) -> Stream(element) {
  unfold(initial, fn(element) { Next(element, f(element)) })
}

pub fn take_while(
  in stream: Stream(element),
  satisfying predicate: fn(element) -> Bool,
) -> Stream(element) {
  case stream {
    Source(cont) -> Source(do_take_while(cont, predicate))
    Flow(source, cont) -> Flow(source, do_take_while(cont, predicate))
  }
}

fn do_take_while(
  continuation: fn(in) -> Action(in, out),
  predicate: fn(out) -> Bool,
) -> fn(in) -> Action(in, out) {
  fn(in) {
    case continuation(in) {
      Stop -> Stop
      Continue(next) -> Continue(do_take_while(next, predicate))
      Emit(e, next) ->
        case predicate(e) {
          True -> Emit(e, do_take_while(next, predicate))
          False -> Stop
        }
    }
  }
}

pub fn drop_while(
  in stream: Stream(element),
  satisfying predicate: fn(element) -> Bool,
) -> Stream(element) {
  case stream {
    Source(cont) -> Source(do_drop_while(cont, predicate))
    Flow(source, cont) -> Flow(source, do_drop_while(cont, predicate))
  }
}

fn do_drop_while(
  continuation: fn(in) -> Action(in, out),
  predicate: fn(out) -> Bool,
) -> fn(in) -> Action(in, out) {
  fn(in) {
    case continuation(in) {
      Stop -> Stop
      Continue(next) -> Continue(do_take_while(next, predicate))
      Emit(e, next) ->
        case predicate(e) {
          True -> Continue(do_drop_while(next, predicate))
          False -> Emit(e, next)
        }
    }
  }
}

pub fn zip(left: Stream(a), right: Stream(b)) -> Stream(#(a, b)) {
  let source =
    fn() {
      use left <- result.try(start(left))
      use right <- result.try(start(right))
      zip.start(left, right)
    }
    |> unsafe_coerce
  Flow(source, unsafe_coerce(identity()))
}

fn next_element(stream: fn(in) -> Action(in, a)) -> fn(in) -> Action(in, a) {
  fn(in) {
    case stream(in) {
      Stop -> Stop
      Continue(next_left) -> Continue(next_element(next_left))
      Emit(el_left, next_left) -> Emit(el_left, next_element(next_left))
    }
  }
}

pub fn intersperse(
  over stream: Stream(element),
  with elem: element,
) -> Stream(element) {
  let source =
    fn() {
      use source <- result.try(start(stream))
      intersperse.start(source, elem)
    }
    |> unsafe_coerce
  Flow(source, unsafe_coerce(identity()))
}

pub fn once(f: fn() -> element) -> Stream(element) {
  Source(fn(_) { Emit(f(), stop) })
}

pub fn interleave(
  left: Stream(element),
  with right: Stream(element),
) -> Stream(element) {
  let source =
    fn() {
      use left_source <- result.try(start(left))
      use right_source <- result.try(start(right))
      interleave.start(left_source, right_source)
    }
    |> unsafe_coerce

  Flow(source, unsafe_coerce(identity()))
}

pub fn try_fold(
  over stream: Stream(element),
  from initial: acc,
  with f: fn(acc, element) -> Result(acc, err),
) -> Result(Result(acc, err), StartError) {
  use source <- result.try(start(stream))
  use sub <- result.map(try_fold.start(source, initial, f))
  process.receive_forever(sub)
}

pub fn emit(element: a, next: fn() -> Stream(a)) -> Stream(a) {
  use _ <- Source
  use in <- Emit(element)
  case next() {
    Source(cont) -> cont(in)
    Flow(_, cont) -> cont(in)
  }
}

pub fn prepend(stream: Stream(a), element: a) -> Stream(a) {
  use <- emit(element)
  stream
}

@external(erlang, "kino_ffi", "identity")
fn unsafe_coerce(value: a) -> anything
