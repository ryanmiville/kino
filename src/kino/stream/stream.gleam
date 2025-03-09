import gleam/bool
import gleam/erlang/process.{type Subject, Normal}
import gleam/function
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor.{type StartError}
import gleam/result
import gleam/string
import logging

pub type Nothing

type Action(in, out) {
  Stop
  Continue(out, fn(in) -> Action(in, out))
}

type Stage(element) =
  Result(Subject(Pull(element)), StartError)

pub type Step(element, state) {
  Next(element: element, state: state)
  Done
}

type X

pub opaque type Stream(element) {
  Stream(
    source: Option(fn() -> Stage(X)),
    continuation: fn(X) -> Action(X, element),
  )
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
      Continue(e, continuation) -> Continue(f(e), do_map(continuation, f))
    }
  }
}

pub fn async_map(stream: Stream(a), f: fn(a) -> b) -> Stream(b) {
  case stream {
    Stream(None, continuation) -> do_async_map(unsafe_coerce(continuation), f)
    Stream(Some(source), flow) -> {
      let new_source = fn() { merge_stages(source(), flow) }
      let new_flow = do_unfold(Nil, fn(acc, a) { Next(f(a), acc) })
      Stream(unsafe_coerce(new_source), unsafe_coerce(new_flow))
    }
  }
}

fn do_async_map(
  continuation: fn(Nil) -> Action(Nil, a),
  f: fn(a) -> b,
) -> Stream(b) {
  let action = do_unfold(Nil, fn(acc, a) { Next(f(a), acc) })
  Stream(
    Some(fn() { start_source(continuation) |> unsafe_coerce }),
    unsafe_coerce(action),
  )
}

fn merge_stages(
  source: Stage(X),
  flow: fn(X) -> Action(X, element),
) -> Stage(element) {
  use source <- result.try(source)
  start_flow(source, flow)
}

pub fn empty() -> Stream(element) {
  Stream(None, fn(_) { Stop })
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
      Next(x, acc) -> Continue(x, do_unfold(acc, f))
      Done -> Stop
    }
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
    Stream(Some(source), flow) -> merge_stages(source(), flow)
  }
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
    Continue(chunk, emit) -> {
      logging.log(logging.Debug, "source: " <> string.inspect(chunk))
      process.send(message.reply_to, Some(chunk))
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
    source: Subject(Pull(in)),
    sink: Subject(Push(out)),
    process: fn(in) -> Action(in, out),
  )
}

fn start_flow(
  source: Subject(Pull(in)),
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
        Flow(self:, as_sink:, as_source:, source:, sink: dummy, process:)
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
  case message {
    FlowPush(Some(element)) -> {
      let before = string.inspect(element)
      case flow.process(element) {
        Continue(element, process) -> {
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
      process.send(flow.sink, None)
      actor.Stop(Normal)
    }
    FlowPull(Pull(sink)) -> {
      process.send(flow.source, Pull(flow.as_sink))
      Flow(..flow, sink:) |> actor.continue
    }
  }
}
