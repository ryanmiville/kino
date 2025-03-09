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

type Action(element) {
  Stop
  Continue(element, fn() -> Action(element))
}

type FlowAction(in, out) {
  FlowStop
  FlowContinue(out, fn(in) -> FlowAction(in, out))
}

type Stage(element) =
  Result(Subject(Pull(element)), StartError)

pub type Step(element, state) {
  Next(element: element, state: state)
  Done
}

type X

pub opaque type Stream(element) {
  Source(continuation: fn() -> Action(element))
  Stream(source: fn() -> Stage(X), flow: fn(X) -> FlowAction(X, element))
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
  case stream {
    Source(continuation) -> Source(map_loop(continuation, f))
    Stream(source, flow) -> Stream(source, flow_map_loop(flow, f))
  }
}

fn map_loop(continuation: fn() -> Action(a), f: fn(a) -> b) -> fn() -> Action(b) {
  fn() {
    case continuation() {
      Stop -> Stop
      Continue(e, continuation) -> Continue(f(e), map_loop(continuation, f))
    }
  }
}

fn flow_map_loop(
  continuation: fn(in) -> FlowAction(in, a),
  f: fn(a) -> b,
) -> fn(in) -> FlowAction(in, b) {
  fn(in) {
    case continuation(in) {
      FlowStop -> FlowStop
      FlowContinue(e, continuation) ->
        FlowContinue(f(e), flow_map_loop(continuation, f))
    }
  }
}

pub fn async_map(stream: Stream(a), f: fn(a) -> b) -> Stream(b) {
  case stream {
    Source(continuation) -> do_async_map(continuation, f)
    Stream(source, flow) -> {
      let new_source = fn() { merge_stages(source(), flow) }
      let new_flow = unfold_flow_loop(Nil, fn(acc, a) { Next(f(a), acc) })
      Stream(unsafe_coerce(new_source), unsafe_coerce(new_flow))
    }
  }
}

fn do_async_map(continuation: fn() -> Action(a), f: fn(a) -> b) -> Stream(b) {
  let action = unfold_flow_loop(Nil, fn(acc, a) { Next(f(a), acc) })
  Stream(
    fn() { start_source(continuation) |> unsafe_coerce },
    unsafe_coerce(action),
  )
}

fn merge_stages(
  source: Stage(X),
  flow: fn(X) -> FlowAction(X, element),
) -> Stage(element) {
  use source <- result.try(source)
  start_flow(source, flow)
}

fn flow_action(f: fn(a) -> b) -> fn() -> Action(fn(a) -> b) {
  fn() { Continue(f, flow_action(f)) }
}

fn unfold_flow_loop(
  initial: acc,
  f: fn(acc, in) -> Step(out, acc),
) -> fn(in) -> FlowAction(in, out) {
  fn(in) {
    case f(initial, in) {
      Next(x, acc) -> FlowContinue(x, unfold_flow_loop(acc, f))
      Done -> FlowStop
    }
  }
}

pub fn empty() -> Stream(element) {
  Source(fn() { Stop })
}

pub fn take(stream: Stream(element), desired: Int) -> Stream(element) {
  use <- bool.lazy_guard(desired <= 0, empty)
  case stream {
    Source(continuation) -> source_take(continuation, desired) |> Source
    Stream(source, flow) -> flow_take(flow, desired) |> Stream(source, _)
  }
}

fn source_take(
  continuation: fn() -> Action(e),
  desired: Int,
) -> fn() -> Action(e) {
  fn() {
    case desired > 0 {
      False -> Stop
      True ->
        case continuation() {
          Stop -> Stop
          Continue(e, next) -> Continue(e, source_take(next, desired - 1))
        }
    }
  }
}

fn flow_take(
  continuation: fn(in) -> FlowAction(in, out),
  desired: Int,
) -> fn(in) -> FlowAction(in, out) {
  fn(in) {
    case desired > 0 {
      False -> FlowStop
      True ->
        case continuation(in) {
          FlowStop -> FlowStop
          FlowContinue(e, next) -> FlowContinue(e, flow_take(next, desired - 1))
        }
    }
  }
}

pub fn unfold(
  from initial: acc,
  with f: fn(acc) -> Step(element, acc),
) -> Stream(element) {
  initial
  |> unfold_loop(f)
  |> Source
}

// Creating Sources
fn unfold_loop(
  initial: acc,
  f: fn(acc) -> Step(element, acc),
) -> fn() -> Action(element) {
  fn() {
    case f(initial) {
      Next(x, acc) -> Continue(x, unfold_loop(acc, f))
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
    Source(continuation) -> start_source(continuation)
    Stream(source, flow) -> merge_stages(source(), flow)
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
  SourceState(self: Subject(Pull(element)), emit: fn() -> Action(element))
}

fn start_source(
  emit: fn() -> Action(element),
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
  case source.emit() {
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
    process: fn(in) -> FlowAction(in, out),
  )
}

fn start_flow(
  source: Subject(Pull(in)),
  process: fn(in) -> FlowAction(in, out),
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
        FlowContinue(element, process) -> {
          logging.log(
            logging.Debug,
            "flow:   " <> before <> " -> " <> string.inspect(element),
          )
          process.send(flow.sink, Some(element))
          let flow = Flow(..flow, process:)
          actor.continue(flow)
        }
        FlowStop -> {
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
