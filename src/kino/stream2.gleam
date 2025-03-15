import gleam/bool
import gleam/erlang/process.{type Subject, Normal}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/otp/actor
import gleam/otp/task.{type Task}

pub opaque type Stream(element) {
  Stream(pull: fn() -> Option(#(element, Stream(element))))
}

pub type Step(element, state) {
  Next(element: element, state: state)
  Done
}

pub fn unfold(
  from initial: acc,
  with f: fn(acc) -> Step(element, acc),
) -> Stream(element) {
  use <- Stream
  case f(initial) {
    Next(e, next) -> Some(#(e, unfold(next, f)))
    Done -> None
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
  use <- Stream
  case stream.pull() {
    Some(#(value, next)) -> Some(#(f(value), map(next, f)))
    None -> None
  }
}

// pub fn async(stream: Stream(a)) -> Stream(a) {
//   case stream {
//     Source(_) ->
//       Flow(fn() { start(stream) |> unsafe_coerce }, unsafe_coerce(identity()))
//     Flow(source, flow) -> {
//       let new_source = fn() { start_with_flow(source(), flow) }
//       Flow(unsafe_coerce(new_source), unsafe_coerce(identity()))
//     }
//   }
// }

// fn start_with_flow(
//   source: Stage(Dynamic),
//   flow: fn(Dynamic) -> Action(Dynamic, element),
// ) -> Stage(element) {
//   use source <- result.try(source)
//   flow.start([source], flow)
// }

pub fn empty() -> Stream(element) {
  Stream(fn() { None })
}

pub fn take(stream: Stream(element), desired: Int) -> Stream(element) {
  case desired <= 0 {
    True -> empty()
    False -> {
      Stream(fn() {
        case stream.pull() {
          Some(#(e, next)) -> {
            Some(#(e, take(next, desired - 1)))
          }
          None -> None
        }
      })
    }
  }
}

pub fn filter(stream: Stream(a), keeping predicate: fn(a) -> Bool) -> Stream(a) {
  use <- Stream
  case stream.pull() {
    Some(#(e, next)) ->
      case predicate(e) {
        True -> Some(#(e, filter(next, predicate)))
        False -> filter(next, predicate).pull()
      }
    None -> None
  }
}

pub fn fold(
  stream: Stream(element),
  from initial: acc,
  with f: fn(acc, element) -> acc,
) -> Task(acc) {
  use <- task.async
  do_fold(stream, initial, f)
}

fn do_fold(stream: Stream(element), acc: acc, f: fn(acc, element) -> acc) -> acc {
  case stream.pull() {
    Some(#(e, next)) -> do_fold(next, f(acc, e), f)
    None -> acc
  }
}

pub fn to_list(stream: Stream(element)) -> Task(List(element)) {
  let f = fn(acc, x) { [x, ..acc] }
  use <- task.async
  do_fold(stream, [], f) |> list.reverse
}

// fn start(stream: Stream(element)) -> Stage(element) {
//   case stream {
//     Source(continuation) -> source.start(unsafe_coerce(continuation))
//     Flow(source, flow) -> start_with_flow(source(), flow)
//   }
// }

pub fn append(to first: Stream(a), suffix second: Stream(a)) -> Stream(a) {
  use <- Stream
  case first.pull() {
    Some(#(e, next)) -> Some(#(e, append(next, second)))
    None -> second.pull()
  }
}

pub fn flatten(stream: Stream(Stream(a))) -> Stream(a) {
  use <- Stream
  case stream.pull() {
    Some(#(first, rest)) ->
      case first.pull() {
        Some(#(e, next)) -> Some(#(e, append(next, flatten(rest))))
        None -> flatten(rest).pull()
      }
    None -> None
  }
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
  use <- Stream
  case stream.pull() {
    Some(#(e, next)) ->
      case f(e) {
        Ok(e) -> Some(#(e, filter_map(next, f)))
        Error(_) -> filter_map(next, f).pull()
      }
    None -> None
  }
}

pub fn transform(
  over stream: Stream(a),
  from initial: acc,
  with f: fn(acc, a) -> Step(b, acc),
) -> Stream(b) {
  use <- Stream
  case stream.pull() {
    Some(#(e, next)) ->
      case f(initial, e) {
        Done -> None
        Next(e, next_state) -> Some(#(e, transform(next, next_state, f)))
      }
    None -> None
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
  case desired <= 0 {
    True -> stream
    False -> {
      Stream(fn() {
        case stream.pull() {
          Some(#(_, next)) -> drop(next, desired - 1).pull()
          None -> None
        }
      })
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
  use <- Stream
  case stream.pull() {
    Some(#(e, next)) ->
      case predicate(e) {
        True -> Some(#(e, take_while(next, predicate)))
        False -> None
      }
    None -> None
  }
}

pub fn drop_while(
  in stream: Stream(element),
  satisfying predicate: fn(element) -> Bool,
) -> Stream(element) {
  use <- Stream
  case stream.pull() {
    Some(#(e, next)) ->
      case predicate(e) {
        True -> drop_while(next, predicate).pull()
        False -> Some(#(e, next))
      }
    None -> None
  }
}

pub fn zip(left: Stream(a), right: Stream(b)) -> Stream(#(a, b)) {
  use <- Stream
  case left.pull() {
    Some(#(l, l_next)) ->
      case right.pull() {
        Some(#(r, r_next)) -> Some(#(#(l, r), zip(l_next, r_next)))
        None -> None
      }
    None -> None
  }
}

pub fn intersperse(
  over stream: Stream(element),
  with elem: element,
) -> Stream(element) {
  use <- Stream
  case stream.pull() {
    Some(#(e, next)) ->
      case next.pull() {
        None -> Some(#(e, empty()))
        _ -> Some(#(e, Stream(fn() { Some(#(elem, intersperse(next, elem))) })))
      }
    None -> None
  }
}

pub fn once(f: fn() -> element) -> Stream(element) {
  Stream(fn() { Some(#(f(), empty())) })
}

pub fn interleave(
  left: Stream(element),
  with right: Stream(element),
) -> Stream(element) {
  use <- Stream
  case left.pull() {
    None -> right.pull()
    Some(#(l, next)) ->
      Some(#(l, Stream(fn() { interleave(right, next).pull() })))
  }
}

pub fn try_fold(
  over stream: Stream(element),
  from initial: acc,
  with f: fn(acc, element) -> Result(acc, err),
) -> Task(Result(acc, err)) {
  use <- task.async
  do_try_fold(stream, initial, f)
}

fn do_try_fold(
  stream: Stream(element),
  acc: acc,
  f: fn(acc, element) -> Result(acc, err),
) -> Result(acc, err) {
  case stream.pull() {
    Some(#(e, next)) ->
      case f(acc, e) {
        Ok(acc) -> do_try_fold(next, acc, f)
        Error(err) -> Error(err)
      }
    None -> Ok(acc)
  }
}

pub fn emit(element: a, next: fn() -> Stream(a)) -> Stream(a) {
  use <- Stream
  Some(#(element, Stream(fn() { next().pull() })))
}

pub fn prepend(stream: Stream(a), element: a) -> Stream(a) {
  use <- emit(element)
  stream
}

pub fn drain(stream: Stream(a)) -> Stream(nothing) {
  case stream.pull() {
    None -> empty()
    Some(#(_, next)) -> drain(next)
  }
}

// Async ------------------------------------------------------------------------

pub fn async_map(
  stream: Stream(element),
  workers: Int,
  f: fn(element) -> result,
) -> Stream(result) {
  use <- bool.lazy_guard(workers <= 1, fn() { map(stream, f) })
  todo
}

pub fn async_map_unordered(
  stream: Stream(element),
  workers: Int,
  f: fn(element) -> result,
) -> Stream(result) {
  use <- bool.lazy_guard(workers <= 1, fn() { map(stream, f) })
  todo
}

pub fn async_interleave(
  left: Stream(element),
  with right: Stream(element),
) -> Stream(element) {
  todo
}

type Zip(l, r) {
  Left(Option(l))
  Right(Option(r))
}

pub fn async_zip(left: Stream(a), right: Stream(b)) -> Stream(#(a, b)) {
  use <- Stream
  let assert Ok(left) = start_stream(left)
  let assert Ok(right) = start_stream(right)

  let left_sub = process.new_subject()
  let right_sub = process.new_subject()

  let pull = fn() {
    process.send(left, Pull(left_sub))
    process.send(right, Pull(right_sub))
  }
  pull()
  process.new_selector()
  |> process.selecting(left_sub, Left)
  |> process.selecting(right_sub, Right)
  |> do_zip(None, None, pull)
}

fn do_zip(
  selector: process.Selector(Zip(l, r)),
  left: Option(l),
  right: Option(r),
  pull: fn() -> Nil,
) -> Option(#(#(l, r), Stream(#(l, r)))) {
  case left, right {
    Some(left), Some(right) -> {
      pull()
      Some(#(
        #(left, right),
        Stream(fn() { do_zip(selector, None, None, pull) }),
      ))
    }
    _, _ -> {
      case process.select_forever(selector) {
        Left(Some(left)) -> {
          do_zip(selector, Some(left), right, pull)
        }
        Right(Some(right)) -> {
          do_zip(selector, left, Some(right), pull)
        }
        Left(None) -> {
          None
        }
        Right(None) -> {
          None
        }
      }
    }
  }
}

pub fn async_concat(
  streams: List(Stream(element)),
  max_open: Int,
) -> Stream(element) {
  use <- bool.lazy_guard(max_open <= 1, fn() { concat(streams) })

  todo
}

pub fn async_flatten(stream: Stream(Stream(a)), max_open: Int) -> Stream(a) {
  use <- bool.lazy_guard(max_open <= 1, fn() { flatten(stream) })
  todo
}

pub fn concurrently(foreground: Stream(a), background: Stream(b)) -> Stream(a) {
  todo
}

pub fn async_filter(
  stream: Stream(a),
  workers: Int,
  keeping predicate: fn(a) -> Bool,
) -> Stream(a) {
  use <- bool.lazy_guard(workers <= 1, fn() { filter(stream, predicate) })

  todo
}

pub fn async_filter_map(
  stream: Stream(a),
  workers: Int,
  keeping_with f: fn(a) -> Result(b, c),
) -> Stream(b) {
  use <- bool.lazy_guard(workers <= 1, fn() { filter_map(stream, f) })
  todo
}

// Time ------------------------------------------------------------------------

pub fn interrupt_when(stream: Stream(a), interrupt: Stream(Bool)) -> Stream(a) {
  todo
}

pub fn interrupt_after(stream: Stream(a), milliseconds: Int) -> Stream(a) {
  todo
}

pub type Timeout {
  Timeout
}

pub fn timeout(
  stream: Stream(a),
  milliseconds: Int,
) -> Stream(Result(a, Timeout)) {
  todo
}

pub fn timeout_on_pull(
  stream: Stream(a),
  milliseconds: Int,
) -> Stream(Result(a, Timeout)) {
  todo
}

pub fn awake_every(milliseconds: Int) -> Stream(a) {
  todo
}

pub type BackoffStrategy

pub fn retry(
  stream: Stream(Result(a, err)),
  strategy: BackoffStrategy,
  max_attempts: Int,
) -> Stream(a) {
  todo
}

pub fn sleep(milliseconds: Int) -> Stream(a) {
  todo
}

pub fn metered(stream: Stream(a), milliseconds: Int) -> Stream(a) {
  todo
}

pub fn spaced(stream: Stream(a), milliseconds: Int) -> Stream(a) {
  todo
}

pub fn keep_alive(stream: Stream(a), heartbeat: a, max_idle: Int) -> Stream(a) {
  todo
}

pub fn chunk_within(
  stream: Stream(a),
  max_size: Int,
  milliseconds: Int,
) -> Stream(a) {
  todo
}

// Actor -----------------------------------------------------------------------

type Pull(element) {
  Pull(reply_to: Subject(Option(element)))
}

fn start_stream(
  stream: Stream(element),
) -> Result(Subject(Pull(element)), actor.StartError) {
  actor.start(stream, on_message)
}

fn on_message(
  msg: Pull(element),
  stream: Stream(element),
) -> actor.Next(d, Stream(element)) {
  case stream.pull() {
    Some(#(element, next)) -> {
      process.send(msg.reply_to, Some(element))
      actor.continue(next)
    }
    None -> {
      process.send(msg.reply_to, None)
      actor.Stop(Normal)
    }
  }
}
