import gleam/bool
import gleam/erlang/process.{type Subject}
import gleam/function
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/otp/actor
import gleam/otp/task.{type Task}
import kino/pool.{type Pool}

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

pub fn run(stream: Stream(element)) -> Task(Nil) {
  use <- task.async
  do_fold(stream, Nil, fn(_, _) { Nil })
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
  use <- Stream
  do_drain(stream)
}

fn do_drain(stream: Stream(a)) -> Option(nothing) {
  case stream.pull() {
    None -> None
    Some(#(_, next)) -> do_drain(next)
  }
}

pub fn values(stream: Stream(Result(a, e))) -> Stream(a) {
  filter_map(stream, fn(r) { r })
}

// Async ------------------------------------------------------------------------

pub fn par_map(
  stream: Stream(element),
  workers: Int,
  f: fn(element) -> result,
) -> Stream(result) {
  use <- bool.lazy_guard(workers <= 1, fn() { map(stream, f) })
  use <- Stream
  let assert Ok(stream) = start_stream(stream)
  let pool = pool.new(workers)
  let subject = process.new_subject()
  let pull = fn() {
    case process.try_call_forever(stream, Pull) {
      Ok(Some(value)) -> {
        process.send(subject, Some(f(value)))
      }
      _ -> {
        process.send(subject, None)
      }
    }
  }
  let pull = fn() { pool.spawn(pool, pull) }
  repeat_apply(workers, pull)
  par_map_loop(subject, pool, pull)
}

fn repeat_apply(times: Int, f: fn() -> anything) -> Nil {
  case times {
    _ if times < 1 -> Nil
    1 -> f() |> to_nil
    _ -> {
      f()
      repeat_apply(times - 1, f)
    }
  }
}

fn to_nil(_) -> Nil {
  Nil
}

fn par_map_loop(subject, pool, pull) {
  case process.receive_forever(subject) {
    Some(element) -> {
      Some(#(
        element,
        Stream(fn() {
          pull()
          par_map_loop(subject, pool, pull)
        }),
      ))
    }
    None -> {
      pool.wait_forever(pool)
      drain_subject(subject)
    }
  }
}

fn drain_subject(subject) {
  case process.receive(subject, 0) {
    Ok(Some(element)) -> {
      Some(#(element, Stream(fn() { drain_subject(subject) })))
    }
    Ok(None) -> {
      drain_subject(subject)
    }
    Error(Nil) -> {
      None
    }
  }
}

pub fn async_interleave(
  left: Stream(element),
  with right: Stream(element),
) -> Stream(element) {
  use <- Stream
  let assert Ok(left) = start_stream(left)
  let assert Ok(right) = start_stream(right)

  let left_sub = process.new_subject()
  let right_sub = process.new_subject()

  let pull_left = fn() { process.send(left, Pull(left_sub)) }
  let pull_right = fn() { process.send(right, Pull(right_sub)) }
  pull_left()
  pull_right()
  do_async_interleave(left_sub, right_sub, pull_left, pull_right)
}

fn do_async_interleave(
  left: Subject(Option(e)),
  right: Subject(Option(e)),
  pull_left: fn() -> Nil,
  pull_right: fn() -> Nil,
) -> Option(#(e, Stream(e))) {
  case process.receive_forever(left) {
    None -> continue_one(pull_right, right)
    Some(element) -> {
      Some(#(
        element,
        Stream(fn() {
          pull_left()
          do_async_interleave(right, left, pull_right, pull_left)
        }),
      ))
    }
  }
}

fn continue_one(
  pull: fn() -> Nil,
  sink: Subject(Option(element)),
) -> Option(#(element, Stream(element))) {
  case process.receive_forever(sink) {
    None -> None
    Some(element) -> {
      Some(#(
        element,
        Stream(fn() {
          pull()
          continue_one(pull, sink)
        }),
      ))
    }
  }
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
      Some(#(
        #(left, right),
        Stream(fn() {
          pull()
          do_zip(selector, None, None, pull)
        }),
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

pub fn par_concat(
  streams: List(Stream(element)),
  max_open: Int,
) -> Stream(element) {
  use <- bool.guard(streams == [], empty())
  use <- bool.lazy_guard(max_open <= 1, fn() { concat(streams) })
  async_flatten(from_list(streams), max_open)
}

pub fn async_flatten(stream: Stream(Stream(a)), max_open: Int) -> Stream(a) {
  use <- bool.lazy_guard(max_open <= 1, fn() { flatten(stream) })
  use <- Stream
  let out = process.new_subject()
  process.start(linked: True, running: fn() {
    let pool = pool.new(max_open)
    outer_loop(stream, out, pool)
  })
  async_drain_loop(out)
}

fn async_flatten_loop(subject: Subject(Option(a))) -> Option(#(a, Stream(a))) {
  use element <- option.map(process.receive_forever(subject))
  #(element, Stream(fn() { async_flatten_loop(subject) }))
}

fn outer_loop(source: Stream(Stream(a)), out, pool: Pool) {
  case source.pull() {
    Some(#(stream, next)) -> {
      pool.spawn(pool, fn() { inner_loop(stream, out) })
      outer_loop(next, out, pool)
    }
    None -> {
      pool.wait_forever(pool)
      process.send(out, None)
    }
  }
}

fn inner_loop(stream: Stream(a), out) {
  case stream.pull() {
    Some(#(el, next)) -> {
      process.send(out, Some(el))
      inner_loop(next, out)
    }
    None -> {
      Nil
    }
  }
}

type Concurrently(a, b) {
  Foreground(Option(a))
  Background(Option(b))
}

/// if foreground finishes first, background will be stopped. If background
/// finishes first, foreground will NOT be stopped
pub fn concurrently(foreground: Stream(a), background: Stream(b)) -> Stream(a) {
  use <- Stream
  let assert Ok(foreground) = start_stream(foreground)
  let assert Ok(background) = start_stream(background)

  let fg_sub = process.new_subject()
  let bg_sub = process.new_subject()

  let fg_pull = fn() { process.send(foreground, Pull(fg_sub)) }
  let bg_pull = fn() { process.send(background, Pull(bg_sub)) }

  fg_pull()
  bg_pull()

  process.new_selector()
  |> process.selecting(fg_sub, Foreground)
  |> process.selecting(bg_sub, Background)
  |> concurrently_loop(fg_pull, bg_pull)
}

fn concurrently_loop(
  selector: process.Selector(Concurrently(a, b)),
  fg_pull: fn() -> Nil,
  bg_pull: fn() -> Nil,
) -> Option(#(a, Stream(a))) {
  case process.select_forever(selector) {
    Foreground(Some(el)) -> {
      Some(#(
        el,
        Stream(fn() {
          fg_pull()
          concurrently_loop(selector, fg_pull, bg_pull)
        }),
      ))
    }
    Foreground(None) -> {
      None
    }
    Background(Some(_)) -> {
      bg_pull()
      concurrently_loop(selector, fg_pull, bg_pull)
    }
    Background(None) -> {
      concurrently_loop(selector, fg_pull, bg_pull)
    }
  }
}

fn run_background(interrupt, stream: Stream(a)) {
  case process.receive(interrupt, 0) {
    Error(_) -> {
      case stream.pull() {
        None -> Nil
        Some(#(_, next)) -> run_background(interrupt, next)
      }
    }
    Ok(_) -> Nil
  }
}

pub fn async_filter(
  stream: Stream(a),
  workers: Int,
  keeping predicate: fn(a) -> Bool,
) -> Stream(a) {
  use <- bool.lazy_guard(workers <= 1, fn() { filter(stream, predicate) })
  use <- Stream
  let out = process.new_subject()
  process.start(linked: True, running: fn() {
    let pool = pool.new(workers)
    async_filter_pull(stream, predicate, out, pool)
  })
  async_drain_loop(out)
}

fn async_filter_pull(
  stream: Stream(a),
  predicate: fn(a) -> Bool,
  out: Subject(Option(a)),
  pool: Pool,
) -> Nil {
  case stream.pull() {
    Some(#(el, next)) -> {
      pool.spawn(pool, fn() {
        use <- bool.guard(!predicate(el), Nil)
        process.send(out, Some(el))
      })
      async_filter_pull(next, predicate, out, pool)
    }
    None -> {
      pool.wait_forever(pool)
      process.send(out, None)
    }
  }
}

fn async_drain_loop(subject) {
  use element <- option.map(process.receive_forever(subject))
  #(element, Stream(fn() { async_drain_loop(subject) }))
}

pub fn async_filter_map(
  stream: Stream(a),
  workers: Int,
  keeping_with f: fn(a) -> Result(b, c),
) -> Stream(b) {
  use <- bool.lazy_guard(workers <= 1, fn() { filter_map(stream, f) })
  use <- Stream
  let out = process.new_subject()
  process.start(linked: True, running: fn() {
    let pool = pool.new(workers)
    async_filter_map_pull(stream, f, out, pool)
  })
  async_drain_loop(out)
}

fn async_filter_map_pull(
  stream: Stream(a),
  f: fn(a) -> Result(b, c),
  out: Subject(Option(b)),
  pool: Pool,
) -> Nil {
  case stream.pull() {
    Some(#(el, next)) -> {
      pool.spawn(pool, fn() {
        case f(el) {
          Ok(el) -> process.send(out, Some(el))
          Error(_) -> Nil
        }
      })
      async_filter_map_pull(next, f, out, pool)
    }
    None -> {
      pool.wait_forever(pool)
      process.send(out, None)
    }
  }
}

// Time ------------------------------------------------------------------------

type Interrupt(a) {
  Primary(Option(a))
  Interrupter(Option(Bool))
}

pub fn interrupt_when(stream: Stream(a), interrupt: Stream(Bool)) -> Stream(a) {
  do_interrupt_when(stream, interrupt) |> values
}

fn do_interrupt_when(
  stream: Stream(a),
  interrupt: Stream(Bool),
) -> Stream(Result(a, Bool)) {
  use <- Stream
  let assert Ok(stream) = start_stream(stream)
  let assert Ok(interrupt) = start_stream(interrupt)

  let stream_sub = process.new_subject()
  let interrupt_sub = process.new_subject()

  let stream_pull = fn() { process.send(stream, Pull(stream_sub)) }
  let interrupt_pull = fn() { process.send(interrupt, Pull(interrupt_sub)) }

  stream_pull()
  interrupt_pull()

  process.new_selector()
  |> process.selecting(stream_sub, Primary)
  |> process.selecting(interrupt_sub, Interrupter)
  |> interrupt_loop(stream_pull, interrupt_pull)
}

fn interrupt_loop(
  selector: process.Selector(Interrupt(a)),
  stream_pull: fn() -> Nil,
  interrupt_pull: fn() -> Nil,
) -> Option(#(Result(a, Bool), Stream(Result(a, Bool)))) {
  case process.select_forever(selector) {
    Primary(Some(el)) -> {
      Some(#(
        Ok(el),
        Stream(fn() {
          stream_pull()
          interrupt_loop(selector, stream_pull, interrupt_pull)
        }),
      ))
    }
    Primary(None) -> {
      None
    }
    Interrupter(Some(True)) -> {
      Some(#(Error(True), empty()))
    }
    Interrupter(Some(False)) -> {
      interrupt_pull()
      interrupt_loop(selector, stream_pull, interrupt_pull)
    }
    Interrupter(None) -> {
      interrupt_loop(selector, stream_pull, interrupt_pull)
    }
  }
}

pub fn interrupt_after(stream: Stream(a), milliseconds: Int) -> Stream(a) {
  timeout(stream, milliseconds) |> values
}

pub type Timeout {
  Timeout
}

pub fn timeout(
  stream: Stream(a),
  milliseconds: Int,
) -> Stream(Result(a, Timeout)) {
  let interrupt =
    Stream(fn() {
      process.sleep(milliseconds)
      Some(#(True, empty()))
    })

  do_interrupt_when(stream, interrupt)
  |> map(fn(el) {
    case el {
      Ok(el) -> Ok(el)
      Error(_) -> Error(Timeout)
    }
  })
}

type TimeoutOnPull(a) {
  TopTimeout
  TopStream(Option(a))
}

pub fn timeout_on_pull(
  stream: Stream(a),
  milliseconds: Int,
) -> Stream(Result(a, Timeout)) {
  use <- Stream
  let assert Ok(stream) = start_stream(stream)

  let stream_sub = process.new_subject()
  let timeout_sub = process.new_subject()

  let stream_pull = fn() {
    process.send(stream, Pull(stream_sub))
    process.send_after(timeout_sub, milliseconds, TopTimeout)
  }

  let timer = stream_pull()

  process.new_selector()
  |> process.selecting(stream_sub, TopStream)
  |> process.selecting(timeout_sub, function.identity)
  |> timeout_on_pull_loop(stream_pull, timer)
}

fn timeout_on_pull_loop(
  selector: process.Selector(TimeoutOnPull(a)),
  stream_pull: fn() -> process.Timer,
  timer: process.Timer,
) -> Option(#(Result(a, Timeout), Stream(Result(a, Timeout)))) {
  case process.select_forever(selector) {
    TopStream(Some(el)) -> {
      process.cancel_timer(timer)
      Some(#(
        Ok(el),
        Stream(fn() {
          let timer = stream_pull()
          timeout_on_pull_loop(selector, stream_pull, timer)
        }),
      ))
    }
    TopStream(None) -> {
      process.cancel_timer(timer)
      None
    }
    TopTimeout -> {
      Some(#(Error(Timeout), empty()))
    }
  }
}

pub type BackoffStrategy

pub fn retry(
  stream: Stream(Result(a, err)),
  strategy: BackoffStrategy,
  max_attempts: Int,
) -> Stream(Result(a, err)) {
  todo
}

pub fn sleep(milliseconds: Int) -> Stream(a) {
  use <- Stream
  process.sleep(milliseconds)
  None
}

pub fn metered(stream: Stream(a), milliseconds: Int) -> Stream(a) {
  let meter = repeatedly(fn() { process.sleep(milliseconds) })
  async_zip(stream, meter)
  |> map(fn(tup) { tup.0 })
}

pub fn spaced(stream: Stream(a), milliseconds: Int) -> Stream(a) {
  let spacer = repeatedly(fn() { process.sleep(milliseconds) }) |> map(Error)
  let stream = stream |> map(Ok)
  interleave(stream, spacer)
  |> values
}

pub fn keep_alive(stream: Stream(a), heartbeat: a, max_idle: Int) -> Stream(a) {
  use <- Stream
  let assert Ok(stream) = start_stream(stream)

  let stream_sub = process.new_subject()
  let timeout_sub = process.new_subject()

  let stream_pull = fn() { process.send(stream, Pull(stream_sub)) }

  let start_timer = fn() {
    process.send_after(timeout_sub, max_idle, TopTimeout)
  }

  stream_pull()
  let timer = start_timer()

  process.new_selector()
  |> process.selecting(stream_sub, TopStream)
  |> process.selecting(timeout_sub, function.identity)
  |> keep_alive_loop(stream_pull, start_timer, heartbeat, timer)
}

fn keep_alive_loop(
  selector: process.Selector(TimeoutOnPull(a)),
  stream_pull: fn() -> Nil,
  start_timer: fn() -> process.Timer,
  heartbeat: a,
  timer: process.Timer,
) -> Option(#(a, Stream(a))) {
  case process.select_forever(selector) {
    TopStream(Some(el)) -> {
      process.cancel_timer(timer)
      Some(#(
        el,
        Stream(fn() {
          stream_pull()
          let timer = start_timer()
          keep_alive_loop(selector, stream_pull, start_timer, heartbeat, timer)
        }),
      ))
    }
    TopStream(None) -> {
      process.cancel_timer(timer)
      None
    }
    TopTimeout -> {
      Some(#(
        heartbeat,
        Stream(fn() {
          let timer = start_timer()
          keep_alive_loop(selector, stream_pull, start_timer, heartbeat, timer)
        }),
      ))
    }
  }
}

pub fn chunk_within(
  stream: Stream(a),
  max_size: Int,
  milliseconds: Int,
) -> Stream(List(a)) {
  use <- Stream
  let assert Ok(stream) = start_stream(stream)

  let stream_sub = process.new_subject()
  let timeout_sub = process.new_subject()

  let stream_pull = fn() { process.send(stream, Pull(stream_sub)) }

  let start_timer = fn() {
    process.send_after(timeout_sub, milliseconds, TopTimeout)
  }

  stream_pull()
  let timer = start_timer()

  process.new_selector()
  |> process.selecting(stream_sub, TopStream)
  |> process.selecting(timeout_sub, function.identity)
  |> chunk_within_loop(stream_pull, start_timer, timer, max_size, max_size, [])
}

fn chunk_within_loop(
  selector,
  stream_pull,
  start_timer,
  timer,
  max_size,
  space_left,
  chunk,
) {
  case process.select_forever(selector) {
    TopStream(Some(el)) -> {
      case space_left {
        1 -> {
          process.cancel_timer(timer)
          let timer = start_timer()
          Some(#(
            list.reverse(chunk),
            Stream(fn() {
              chunk_within_loop(
                selector,
                stream_pull,
                start_timer,
                timer,
                max_size,
                max_size,
                [],
              )
            }),
          ))
        }
        _ -> {
          chunk_within_loop(
            selector,
            stream_pull,
            start_timer,
            timer,
            max_size,
            space_left - 1,
            [el, ..chunk],
          )
        }
      }
    }
    TopStream(None) -> {
      process.cancel_timer(timer)
      None
    }
    TopTimeout -> {
      let timer = start_timer()
      Some(#(
        list.reverse(chunk),
        Stream(fn() {
          chunk_within_loop(
            selector,
            stream_pull,
            start_timer,
            timer,
            max_size,
            max_size,
            [],
          )
        }),
      ))
    }
  }
}

// Actors ----------------------------------------------------------------------

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
      actor.continue(Stream(fn() { None }))
    }
  }
}
