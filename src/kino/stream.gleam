import gleam/bool
import gleam/erlang/process.{type Subject, Normal}
import gleam/function
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/otp/actor.{type StartError}
import gleam/result
import gleam/string
import logging

type Action(in, out) {
  Stop
  Continue(Option(out), fn(in) -> Action(in, out))
}

type Stage(element) =
  Result(Subject(Pull(element)), StartError)

// A shameful hack
type X

pub opaque type Stream(element) {
  Stream(
    source: Option(fn() -> Stage(X)),
    continuation: fn(X) -> Action(X, element),
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
  |> Stream(None, _)
}

fn do_unfold(
  initial: acc,
  f: fn(acc, in) -> Step(out, acc),
) -> fn(in) -> Action(in, out) {
  fn(in) {
    case f(initial, in) {
      Next(x, acc) -> Continue(Some(x), do_unfold(acc, f))
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
  from_list([element])
}

pub fn map(stream: Stream(a), f: fn(a) -> b) -> Stream(b) {
  Stream(..stream, continuation: do_map(stream.continuation, f))
}

fn do_map(
  continuation: fn(in) -> Action(in, a),
  f: fn(a) -> b,
) -> fn(in) -> Action(in, b) {
  fn(in) {
    case continuation(in) {
      Stop -> Stop
      Continue(e, continuation) ->
        Continue(option.map(e, f), do_map(continuation, f))
    }
  }
}

pub fn async(stream: Stream(a)) -> Stream(a) {
  case stream {
    Stream(None, continuation) -> do_async(unsafe_coerce(continuation))
    Stream(Some(source), flow) -> {
      let new_source = fn() { start_with_flow(source(), flow) }
      Stream(unsafe_coerce(new_source), unsafe_coerce(identity()))
    }
  }
}

fn do_async(continuation: fn(Nil) -> Action(Nil, a)) -> Stream(b) {
  let action = do_unfold(Nil, fn(acc, a) { Next(a, acc) })
  Stream(
    Some(fn() { start_source(continuation) |> unsafe_coerce }),
    unsafe_coerce(action),
  )
}

fn start_with_flow(
  source: Stage(X),
  flow: fn(X) -> Action(X, element),
) -> Stage(element) {
  use source <- result.try(source)
  start_flow([source], flow)
}

pub fn empty() -> Stream(element) {
  Stream(None, stop)
}

pub fn take(stream: Stream(element), desired: Int) -> Stream(element) {
  use <- bool.lazy_guard(desired <= 0, empty)
  Stream(..stream, continuation: do_take(stream.continuation, desired))
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
          Continue(e, next) -> Continue(e, do_take(next, desired - 1))
        }
    }
  }
}

pub fn filter(stream: Stream(a), keeping predicate: fn(a) -> Bool) -> Stream(a) {
  let continuation = do_filter(stream.continuation, predicate)
  Stream(..stream, continuation:)
}

fn do_filter(
  continuation: fn(in) -> Action(in, out),
  predicate: fn(out) -> Bool,
) -> fn(in) -> Action(in, out) {
  fn(in) {
    case continuation(in) {
      Stop -> Stop
      Continue(e, stream) ->
        Continue(filter_option(e, predicate), do_filter(stream, predicate))
    }
  }
}

fn filter_option(option: Option(a), predicate: fn(a) -> Bool) -> Option(a) {
  case option {
    Some(value) -> {
      case predicate(value) {
        True -> Some(value)
        False -> None
      }
    }
    None -> None
  }
}

pub fn fold(
  stream: Stream(element),
  from initial: acc,
  with f: fn(acc, element) -> acc,
) -> Result(acc, StartError) {
  use source <- result.try(start(stream))
  use sub <- result.map(start_sink(source, initial, f))
  process.receive_forever(sub)
}

pub fn to_list(stream: Stream(element)) -> Result(List(element), StartError) {
  let f = fn(acc, x) { [x, ..acc] }
  fold(stream, [], f) |> result.map(list.reverse)
}

fn start(stream: Stream(element)) -> Stage(element) {
  case stream {
    Stream(None, continuation) -> start_source(unsafe_coerce(continuation))
    Stream(Some(source), flow) -> start_with_flow(source(), flow)
  }
}

pub fn append(to first: Stream(a), suffix second: Stream(a)) -> Stream(a) {
  case first, second {
    Stream(None, c1), Stream(None, c2) ->
      Stream(None, append_continuation(c1, c2))

    Stream(None, c1), Stream(Some(s2), c2) -> {
      let source =
        fn() {
          let s1 = start_source(unsafe_coerce(c1))
          use s2 <- result.try(s2())
          let s2 = start_flow([s2], c2)
          merge_sources(s1, s2)
        }
        |> unsafe_coerce
      Stream(Some(source), unsafe_coerce(identity()))
    }

    // Stream(None, c1), Stream(Some(s2), c2) -> {
    //   let s1 = fn() { start_source(unsafe_coerce(c1)) }
    //   let merged = fn() { merge_sources(s1(), s2()) }
    //   Stream(Some(merged), c2)
    // }
    Stream(Some(s1), c1), Stream(None, c2) -> {
      let source = fn() {
        use s1 <- result.try(s1())
        let s1 = start_flow([s1], c1) |> unsafe_coerce
        let s2 = start_source(unsafe_coerce(c2))
        merge_sources(s1, s2)
      }
      Stream(Some(source), unsafe_coerce(identity()))
    }

    Stream(Some(s1), c1), Stream(Some(s2), c2) -> {
      let source =
        fn() {
          use s1 <- result.try(s1())
          let s1 = start_flow([s1], c1)
          use s2 <- result.try(s2())
          let s2 = start_flow([s2], c2)
          merge_sources(s1, s2)
        }
        |> unsafe_coerce
      Stream(Some(source), unsafe_coerce(identity()))
    }
  }
}

fn append_continuation(
  first: fn(in) -> Action(in, a),
  second: fn(in) -> Action(in, a),
) -> fn(in) -> Action(in, a) {
  fn(in) {
    case first(in) {
      Continue(a, next) -> Continue(a, append_continuation(next, second))
      Stop -> second(in)
    }
  }
}

fn merge_sources(first: Stage(a), second: Stage(a)) -> Stage(a) {
  use first <- result.try(first)
  use second <- result.try(second)
  start_flow([first, second], identity())
}

pub fn flatten(stream: Stream(Stream(a))) -> Stream(a) {
  todo
}

fn do_flatten(
  flattened: fn(in) -> Action(in, Stream(a)),
) -> fn(in) -> Action(in, a) {
  todo
}

pub fn flat_map(over stream: Stream(a), with f: fn(a) -> Stream(b)) -> Stream(b) {
  stream |> map(f) |> flatten
}

pub fn filter_map(
  stream: Stream(a),
  keeping_with f: fn(a) -> Result(b, c),
) -> Stream(b) {
  todo
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
  todo
}

pub fn drop(from stream: Stream(element), up_to desired: Int) -> Stream(element) {
  todo
}

pub fn concat(from streams: List(Stream(element))) -> Stream(element) {
  todo
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
  todo
}

pub fn drop_while(
  in stream: Stream(element),
  satisfying predicate: fn(element) -> Bool,
) -> Stream(element) {
  todo
}

pub fn zip(left: Stream(a), right: Stream(b)) -> Stream(#(a, b)) {
  todo
}

pub fn intersperse(
  over stream: Stream(element),
  with elem: element,
) -> Stream(element) {
  todo
}

pub fn once(f: fn() -> element) -> Stream(element) {
  Stream(None, fn(_) { Continue(Some(f()), stop) })
}

pub fn interleave(
  left: Stream(element),
  with right: Stream(element),
) -> Stream(element) {
  todo
}

pub fn try_fold(
  over stream: Stream(element),
  from initial: acc,
  with f: fn(acc, element) -> Result(acc, err),
) -> Result(acc, err) {
  todo
}

pub fn emit(element: a, next: fn() -> Stream(a)) -> Stream(a) {
  Stream(None, fn(_) {
    Continue(Some(element), fn(in) { next().continuation(in) })
  })
}

pub fn prepend(stream: Stream(a), element: a) -> Stream(a) {
  use <- emit(element)
  stream
}

@external(erlang, "kino_ffi", "identity")
fn unsafe_coerce(value: a) -> anything

// -------------------------------
// Source
// -------------------------------
type Pull(element) {
  Pull(reply_to: Subject(Option(element)))
}

type SourceState(element) {
  SourceState(
    self: Subject(Pull(element)),
    emit: fn(Nil) -> Action(Nil, element),
  )
}

fn start_source(
  emit: fn(Nil) -> Action(Nil, element),
) -> Result(Subject(Pull(element)), StartError) {
  actor.Spec(
    init: fn() {
      let self = process.new_subject()
      let selector =
        process.new_selector()
        |> process.selecting(self, function.identity)
      SourceState(self:, emit:)
      |> actor.Ready(selector)
    },
    init_timeout: 1000,
    loop: on_pull,
  )
  |> actor.start_spec
}

fn on_pull(message: Pull(element), source: SourceState(element)) {
  case source.emit(Nil) {
    Continue(Some(chunk), emit) -> {
      logging.log(logging.Debug, "source: " <> string.inspect(chunk))
      process.send(message.reply_to, Some(chunk))
      SourceState(..source, emit:) |> actor.continue
    }
    Continue(None, emit) -> {
      process.send(source.self, message)
      SourceState(..source, emit:) |> actor.continue
    }
    Stop -> {
      process.send(message.reply_to, None)
      actor.Stop(Normal)
    }
  }
}

// -------------------------------
// Sink
// -------------------------------
type Push(element) =
  Option(element)

type Sink(acc, element) {
  Sink(
    self: Subject(Push(element)),
    source: Subject(Pull(element)),
    accumulator: acc,
    fold: fn(acc, element) -> acc,
    receiver: Subject(acc),
  )
}

fn start_sink(
  source: Subject(Pull(element)),
  initial: acc,
  f: fn(acc, element) -> acc,
) -> Result(Subject(acc), StartError) {
  let receiver = process.new_subject()
  actor.Spec(
    init: fn() {
      let self = process.new_subject()
      let selector =
        process.new_selector()
        |> process.selecting(self, function.identity)
      process.send(source, Pull(self))
      Sink(self, source, initial, f, receiver)
      |> actor.Ready(selector)
    },
    init_timeout: 1000,
    loop: on_push,
  )
  |> actor.start_spec
  |> result.map(fn(_) { receiver })
}

fn on_push(message: Push(element), sink: Sink(acc, element)) {
  case message {
    Some(element) -> {
      logging.log(logging.Debug, "sink:   " <> string.inspect(element))
      let accumulator = sink.fold(sink.accumulator, element)
      let sink = Sink(..sink, accumulator:)
      process.send(sink.source, Pull(sink.self))
      actor.continue(sink)
    }
    None -> {
      logging.log(logging.Debug, "sink:   None")
      process.send(sink.receiver, sink.accumulator)
      actor.Stop(Normal)
    }
  }
}

// -------------------------------
// Flow
// -------------------------------
type Message(in, out) {
  FlowPush(Push(in))
  FlowPull(Pull(out))
}

type Flow(in, out) {
  Flow(
    self: Subject(Message(in, out)),
    as_sink: Subject(Push(in)),
    as_source: Subject(Pull(out)),
    sources: List(Subject(Pull(in))),
    sink: Subject(Push(out)),
    process: fn(in) -> Action(in, out),
  )
}

fn start_flow(
  sources: List(Subject(Pull(in))),
  process: fn(in) -> Action(in, out),
) -> Result(Subject(Pull(out)), StartError) {
  let receiver = process.new_subject()
  let dummy = process.new_subject()
  actor.Spec(
    init: fn() {
      let self = process.new_subject()
      let as_source = process.new_subject()
      let as_sink = process.new_subject()

      let selector =
        process.new_selector()
        |> process.selecting(self, function.identity)
        |> process.selecting(as_source, FlowPull)
        |> process.selecting(as_sink, FlowPush)
      let flow =
        Flow(
          self:,
          as_sink:,
          as_source:,
          sources: sources,
          sink: dummy,
          process:,
        )
      process.send(receiver, as_source)
      actor.Ready(flow, selector)
    },
    init_timeout: 1000,
    loop: on_message,
  )
  |> actor.start_spec
  |> result.map(fn(_) { process.receive_forever(receiver) })
}

fn on_message(message: Message(in, out), flow: Flow(in, out)) {
  use <- bool.guard(flow.sources == [], actor.Stop(Normal))
  let assert [source, ..sources] = flow.sources
  case message {
    FlowPush(Some(element)) -> {
      let before = string.inspect(element)
      case flow.process(element) {
        Continue(None, process) -> {
          process.send(source, Pull(flow.as_sink))
          actor.continue(Flow(..flow, process:))
        }
        Continue(Some(element), process) -> {
          logging.log(
            logging.Debug,
            "flow:   " <> before <> " -> " <> string.inspect(element),
          )
          process.send(flow.sink, Some(element))
          let flow = Flow(..flow, process:)
          actor.continue(flow)
        }
        Stop -> {
          process.send(flow.sink, None)
          actor.Stop(Normal)
        }
      }
    }
    FlowPush(None) -> {
      case sources {
        [] -> {
          process.send(flow.sink, None)
          actor.Stop(Normal)
        }
        _ -> {
          logging.log(logging.Debug, "flow:   next source")
          process.send(flow.as_source, Pull(flow.sink))
          Flow(..flow, sources:) |> actor.continue
        }
      }
      // process.send(flow.sink, None)
      // actor.Stop(Normal)
    }
    FlowPull(Pull(sink)) -> {
      process.send(source, Pull(flow.as_sink))
      Flow(..flow, sink:) |> actor.continue
    }
  }
}
