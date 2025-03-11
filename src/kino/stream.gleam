import gleam/bool
import gleam/dynamic.{type Dynamic}
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

pub opaque type Stream(element) {
  Stream(
    source: Option(fn() -> Stage(Dynamic)),
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
    Stream(None, _) ->
      Stream(
        Some(fn() { start(stream) |> unsafe_coerce }),
        unsafe_coerce(identity()),
      )
    Stream(Some(source), flow) -> {
      let new_source = fn() { start_with_flow(source(), flow) }
      Stream(unsafe_coerce(new_source), unsafe_coerce(identity()))
    }
  }
}

fn start_with_flow(
  source: Stage(Dynamic),
  flow: fn(Dynamic) -> Action(Dynamic, element),
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
          merge_stages(s1, s2)
        }
        |> unsafe_coerce
      Stream(Some(source), unsafe_coerce(identity()))
    }

    Stream(Some(s1), c1), Stream(None, c2) -> {
      let source = fn() {
        use s1 <- result.try(s1())
        let s1 = start_flow([s1], c1) |> unsafe_coerce
        let s2 = start_source(unsafe_coerce(c2))
        merge_stages(s1, s2)
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
          merge_stages(s1, s2)
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

fn merge_stages(first: Stage(a), second: Stage(a)) -> Stage(a) {
  use first <- result.try(first)
  use second <- result.try(second)
  start_flow([first, second], identity())
}

pub fn flatten(stream: Stream(Stream(a))) -> Stream(a) {
  let source =
    fn() {
      use s <- result.try(start(stream))
      start_flattener(s)
    }
    |> unsafe_coerce
  Stream(Some(source), unsafe_coerce(identity()))
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
  Stream(..stream, continuation: do_filter_map(stream.continuation, f))
}

fn do_filter_map(
  continuation: fn(in) -> Action(in, a),
  f: fn(a) -> Result(b, c),
) -> fn(in) -> Action(in, b) {
  fn(in) {
    case continuation(in) {
      Stop -> Stop
      Continue(None, next) -> Continue(None, do_filter_map(next, f))
      Continue(Some(e), next) ->
        case f(e) {
          Ok(e) -> Continue(Some(e), do_filter_map(next, f))
          Error(_) -> Continue(None, do_filter_map(next, f))
        }
    }
  }
}

pub fn transform(
  over stream: Stream(a),
  from initial: acc,
  with f: fn(acc, a) -> Step(b, acc),
) -> Stream(b) {
  Stream(
    ..stream,
    continuation: transform_loop(stream.continuation, initial, f),
  )
}

fn transform_loop(
  continuation: fn(in) -> Action(in, a),
  state: acc,
  f: fn(acc, a) -> Step(b, acc),
) -> fn(in) -> Action(in, b) {
  fn(in) {
    case continuation(in) {
      Stop -> Stop
      Continue(None, next) -> Continue(None, transform_loop(next, state, f))
      Continue(Some(el), next) ->
        case f(state, el) {
          Done -> Stop
          Next(yield, next_state) ->
            Continue(Some(yield), transform_loop(next, next_state, f))
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
  Stream(..stream, continuation: do_drop(stream.continuation, desired))
}

fn do_drop(
  continuation: fn(in) -> Action(in, out),
  desired: Int,
) -> fn(in) -> Action(in, out) {
  fn(in) {
    case continuation(in) {
      Stop -> Stop
      Continue(e, next) ->
        case desired > 0 {
          True -> Continue(None, do_drop(next, desired - 1))
          False -> Continue(e, next)
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
  Stream(..stream, continuation: do_take_while(stream.continuation, predicate))
}

fn do_take_while(
  continuation: fn(in) -> Action(in, out),
  predicate: fn(out) -> Bool,
) -> fn(in) -> Action(in, out) {
  fn(in) {
    case continuation(in) {
      Stop -> Stop
      Continue(None, next) -> Continue(None, do_take_while(next, predicate))
      Continue(Some(e), next) ->
        case predicate(e) {
          True -> Continue(Some(e), do_take_while(next, predicate))
          False -> Stop
        }
    }
  }
}

pub fn drop_while(
  in stream: Stream(element),
  satisfying predicate: fn(element) -> Bool,
) -> Stream(element) {
  Stream(..stream, continuation: do_drop_while(stream.continuation, predicate))
}

fn do_drop_while(
  continuation: fn(in) -> Action(in, out),
  predicate: fn(out) -> Bool,
) -> fn(in) -> Action(in, out) {
  fn(in) {
    case continuation(in) {
      Stop -> Stop
      Continue(None, next) -> Continue(None, do_take_while(next, predicate))
      Continue(Some(e), next) ->
        case predicate(e) {
          True -> Continue(None, do_drop_while(next, predicate))
          False -> Continue(Some(e), next)
        }
    }
  }
}

pub fn zip(left: Stream(a), right: Stream(b)) -> Stream(#(a, b)) {
  let source =
    fn() {
      use left <- result.try(start(left))
      use right <- result.try(start(right))
      start_zipper(left, right)
    }
    |> unsafe_coerce
  Stream(Some(source), unsafe_coerce(identity()))
}

fn next_element(stream: fn(in) -> Action(in, a)) -> fn(in) -> Action(in, a) {
  fn(in) {
    case stream(in) {
      Stop -> Stop
      Continue(None, next_left) -> Continue(None, next_element(next_left))
      Continue(Some(el_left), next_left) ->
        Continue(Some(el_left), next_element(next_left))
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
      start_intersperser(source, elem)
    }
    |> unsafe_coerce
  Stream(Some(source), unsafe_coerce(identity()))
}

pub fn once(f: fn() -> element) -> Stream(element) {
  Stream(None, fn(_) { Continue(Some(f()), stop) })
}

pub fn interleave(
  left: Stream(element),
  with right: Stream(element),
) -> Stream(element) {
  let source =
    fn() {
      use left_source <- result.try(start(left))
      use right_source <- result.try(start(right))
      start_interleaver(left_source, right_source)
    }
    |> unsafe_coerce

  Stream(Some(source), unsafe_coerce(identity()))
}

pub fn try_fold(
  over stream: Stream(element),
  from initial: acc,
  with f: fn(acc, element) -> Result(acc, err),
) -> Result(Result(acc, err), StartError) {
  use source <- result.try(start(stream))
  use sub <- result.map(start_try_sink(source, initial, f))
  process.receive_forever(sub)
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
    }
    FlowPull(Pull(sink)) -> {
      process.send(source, Pull(flow.as_sink))
      Flow(..flow, sink:) |> actor.continue
    }
  }
}

// -------------------------------
// Flattener
// -------------------------------
type FlattenMessage(a) {
  StreamPush(Push(Stream(a)))
  ElementPush(Push(a))
  ElementPull(Pull(a))
}

type Flattener(a) {
  Flattener(
    initial: Subject(Pull(Stream(a))),
    current: Option(Subject(Pull(a))),
    self: Subject(FlattenMessage(a)),
    as_source: Subject(Pull(a)),
    as_sink: Subject(Push(a)),
    as_stream_sink: Subject(Push(Stream(a))),
    waiting: Bool,
    sink: Subject(Push(a)),
  )
}

fn start_flattener(
  source: Subject(Pull(Stream(a))),
) -> Result(Subject(Pull(a)), StartError) {
  let receiver = process.new_subject()
  let dummy = process.new_subject()
  actor.Spec(
    init: fn() {
      let self = process.new_subject()
      let as_source = process.new_subject()
      let as_sink = process.new_subject()
      let as_stream_sink = process.new_subject()

      let selector =
        process.new_selector()
        |> process.selecting(self, function.identity)
        |> process.selecting(as_source, ElementPull)
        |> process.selecting(as_sink, ElementPush)
        |> process.selecting(as_stream_sink, StreamPush)
      let flow =
        Flattener(
          initial: source,
          current: None,
          self:,
          as_sink:,
          as_source:,
          as_stream_sink:,
          sink: dummy,
          waiting: False,
        )
      process.send(receiver, as_source)
      actor.Ready(flow, selector)
    },
    init_timeout: 1000,
    loop: flattener_on_message,
  )
  |> actor.start_spec
  |> result.map(fn(_) { process.receive_forever(receiver) })
}

fn flattener_on_message(message: FlattenMessage(a), flow: Flattener(a)) {
  case message {
    StreamPush(None) -> {
      process.send(flow.sink, None)
      actor.Stop(Normal)
    }
    StreamPush(Some(stream)) -> {
      // TODO
      let assert Ok(source) = start(stream)
      process.send(source, Pull(flow.as_sink))
      Flattener(..flow, current: Some(source))
      |> actor.continue
    }
    ElementPush(Some(element)) -> {
      process.send(flow.sink, Some(element))
      actor.continue(flow)
    }
    ElementPush(None) -> {
      process.send(flow.initial, Pull(flow.as_stream_sink))
      Flattener(..flow, waiting: True, current: None)
      |> actor.continue
    }
    ElementPull(Pull(sink)) -> {
      case flow.current {
        Some(source) -> {
          process.send(source, Pull(flow.as_sink))
          Flattener(..flow, sink:)
          |> actor.continue
        }
        None -> {
          case flow.waiting {
            True -> actor.continue(flow)
            False -> {
              process.send(flow.initial, Pull(flow.as_stream_sink))
              Flattener(..flow, waiting: True, current: None, sink:)
              |> actor.continue
            }
          }
        }
      }
    }
  }
}

// -------------------------------
// Zipper
// -------------------------------
type ZipMessage(a, b) {
  LeftPush(Push(a))
  RightPush(Push(b))
  ZipPull(Pull(#(a, b)))
}

type Zipper(a, b) {
  Zipper(
    left_source: Subject(Pull(a)),
    right_source: Subject(Pull(b)),
    self: Subject(ZipMessage(a, b)),
    as_source: Subject(Pull(#(a, b))),
    as_left_sink: Subject(Push(a)),
    as_right_sink: Subject(Push(b)),
    left_buffer: List(a),
    // Buffer for left elements
    right_buffer: List(b),
    // Buffer for right elements
    sink: Subject(Push(#(a, b))),
  )
}

fn start_zipper(
  left_source: Subject(Pull(a)),
  right_source: Subject(Pull(b)),
) -> Result(Subject(Pull(#(a, b))), StartError) {
  let receiver = process.new_subject()
  let dummy = process.new_subject()

  actor.Spec(
    init: fn() {
      let self = process.new_subject()
      let as_source = process.new_subject()
      let as_left_sink = process.new_subject()
      let as_right_sink = process.new_subject()

      let selector =
        process.new_selector()
        |> process.selecting(self, function.identity)
        |> process.selecting(as_source, ZipPull)
        |> process.selecting(as_left_sink, LeftPush)
        |> process.selecting(as_right_sink, RightPush)

      let zipper =
        Zipper(
          left_source: left_source,
          right_source: right_source,
          self: self,
          as_source: as_source,
          as_left_sink: as_left_sink,
          as_right_sink: as_right_sink,
          left_buffer: [],
          right_buffer: [],
          sink: dummy,
        )

      process.send(receiver, as_source)
      actor.Ready(zipper, selector)
    },
    init_timeout: 1000,
    loop: zipper_on_message,
  )
  |> actor.start_spec
  |> result.map(fn(_) { process.receive_forever(receiver) })
}

fn zipper_on_message(message: ZipMessage(a, b), zipper: Zipper(a, b)) {
  case message {
    // Handle pull requests from downstream
    ZipPull(Pull(sink)) -> {
      // Store the sink for later
      let zipper = Zipper(..zipper, sink: sink)

      // Try to emit a tuple if we have elements in both buffers
      case zipper.left_buffer, zipper.right_buffer {
        [left, ..left_rest], [right, ..right_rest] -> {
          // We have elements in both buffers, emit a tuple
          process.send(zipper.sink, Some(#(left, right)))

          // Continue with updated buffers
          Zipper(..zipper, left_buffer: left_rest, right_buffer: right_rest)
          |> actor.continue
        }
        _, _ -> {
          // We need more elements, request from sources if buffers are empty
          case zipper.left_buffer {
            [] -> process.send(zipper.left_source, Pull(zipper.as_left_sink))
            _ -> Nil
          }

          case zipper.right_buffer {
            [] -> process.send(zipper.right_source, Pull(zipper.as_right_sink))
            _ -> Nil
          }

          actor.continue(zipper)
        }
      }
    }

    // Handle elements from left source
    LeftPush(Some(element)) -> {
      let zipper =
        Zipper(
          ..zipper,
          left_buffer: list.append(zipper.left_buffer, [element]),
        )

      // Try to emit if we have elements from both sources
      case zipper.right_buffer {
        [right, ..right_rest] -> {
          case zipper.left_buffer {
            [left, ..left_rest] -> {
              process.send(zipper.sink, Some(#(left, right)))
              Zipper(..zipper, left_buffer: left_rest, right_buffer: right_rest)
              |> actor.continue
            }
            [] -> actor.continue(zipper)
            // This shouldn't happen due to the append above
          }
        }
        [] -> {
          // We need more elements from the right source
          process.send(zipper.right_source, Pull(zipper.as_right_sink))
          actor.continue(zipper)
        }
      }
    }

    // Handle elements from right source
    RightPush(Some(element)) -> {
      let zipper =
        Zipper(
          ..zipper,
          right_buffer: list.append(zipper.right_buffer, [element]),
        )

      // Try to emit if we have elements from both sources
      case zipper.left_buffer {
        [left, ..left_rest] -> {
          case zipper.right_buffer {
            [right, ..right_rest] -> {
              process.send(zipper.sink, Some(#(left, right)))
              Zipper(..zipper, left_buffer: left_rest, right_buffer: right_rest)
              |> actor.continue
            }
            [] -> actor.continue(zipper)
            // This shouldn't happen due to the append above
          }
        }
        [] -> {
          // We need more elements from the left source
          process.send(zipper.left_source, Pull(zipper.as_left_sink))
          actor.continue(zipper)
        }
      }
    }

    // Handle end of stream from either source
    LeftPush(None) | RightPush(None) -> {
      // If either source is done, we're done
      process.send(zipper.sink, None)
      actor.Stop(Normal)
    }
  }
}

// -------------------------------
// Intersperser
// -------------------------------
type IntersperseMessage(element) {
  IntersperserPush(Push(element))
  IntersperserPull(Pull(element))
}

type IntersperserState(element) {
  ElementNext
  // Waiting for next element from source
  SeparatorNext
  // Ready to insert separator before next element
}

type Intersperser(element) {
  Intersperser(
    source: Subject(Pull(element)),
    self: Subject(IntersperseMessage(element)),
    as_source: Subject(Pull(element)),
    as_sink: Subject(Push(element)),
    sink: Subject(Push(element)),
    separator: element,
    state: IntersperserState(element),
    // Holds the next element to emit after separator
  )
}

fn start_intersperser(
  source: Subject(Pull(element)),
  separator: element,
) -> Result(Subject(Pull(element)), StartError) {
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
        |> process.selecting(as_source, IntersperserPull)
        |> process.selecting(as_sink, IntersperserPush)

      let intersperser =
        Intersperser(
          source: source,
          self: self,
          as_source: as_source,
          as_sink: as_sink,
          sink: dummy,
          separator: separator,
          state: ElementNext,
        )

      process.send(receiver, as_source)
      actor.Ready(intersperser, selector)
    },
    init_timeout: 1000,
    loop: intersperser_on_message,
  )
  |> actor.start_spec
  |> result.map(fn(_) { process.receive_forever(receiver) })
}

fn intersperser_on_message(
  message: IntersperseMessage(element),
  intersperser: Intersperser(element),
) {
  case message {
    // Handle pull requests from downstream
    IntersperserPull(Pull(sink)) -> {
      let intersperser = Intersperser(..intersperser, sink: sink)

      case intersperser.state {
        // Initial state or need element - request one from source
        ElementNext -> {
          process.send(intersperser.source, Pull(intersperser.as_sink))
          actor.continue(intersperser)
        }

        // Ready to insert separator and have next element
        SeparatorNext -> {
          // Send separator first
          process.send(intersperser.sink, Some(intersperser.separator))

          // Next time we'll send the element we're holding
          Intersperser(..intersperser, state: ElementNext)
          |> actor.continue
        }
      }
    }

    // Handle elements from source
    IntersperserPush(Some(element)) -> {
      case intersperser.state {
        // First element, emit directly
        // Initial -> {
        //   process.send(intersperser.sink, Some(element))
        //   Intersperser(..intersperser, state: SeparatorNext, next_element: None)
        //   |> actor.continue
        // }
        // Need element - this means we previously sent the separator
        ElementNext -> {
          // Send the element we were holding from before
          process.send(intersperser.sink, Some(element))

          // Next we'll need to insert separator
          Intersperser(..intersperser, state: SeparatorNext)
          |> actor.continue
        }

        // this shouldn't happen
        SeparatorNext -> {
          actor.continue(intersperser)
        }
      }
    }

    // Handle end of stream
    IntersperserPush(None) -> {
      // Signal end of stream downstream
      process.send(intersperser.sink, None)
      actor.Stop(Normal)
    }
  }
}

// -------------------------------
// Interleaver
// -------------------------------
type InterleaveMessage(element) {
  InterleavePush(Push(element))
  InterleavePull(Pull(element))
}

type InterleaverState {
  Left
  Right
}

type Interleaver(element) {
  Interleaver(
    left_source: Subject(Pull(element)),
    right_source: Subject(Pull(element)),
    self: Subject(InterleaveMessage(element)),
    as_source: Subject(Pull(element)),
    as_sink: Subject(Push(element)),
    current_state: InterleaverState,
    // Track which source to pull from next
    sink: Subject(Push(element)),
    left_done: Bool,
    // Track if left source is done
    right_done: Bool,
    // Track if right source is done
  )
}

fn start_interleaver(
  left_source: Subject(Pull(element)),
  right_source: Subject(Pull(element)),
) -> Result(Subject(Pull(element)), StartError) {
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
        |> process.selecting(as_source, InterleavePull)
        |> process.selecting(as_sink, InterleavePush)

      let interleaver =
        Interleaver(
          left_source: left_source,
          right_source: right_source,
          self: self,
          as_source: as_source,
          as_sink: as_sink,
          current_state: Left,
          sink: dummy,
          left_done: False,
          right_done: False,
        )

      process.send(receiver, as_source)
      actor.Ready(interleaver, selector)
    },
    init_timeout: 1000,
    loop: interleaver_on_message,
  )
  |> actor.start_spec
  |> result.map(fn(_) { process.receive_forever(receiver) })
}

fn interleaver_on_message(
  message: InterleaveMessage(element),
  interleaver: Interleaver(element),
) {
  case message {
    // Handle pull requests from downstream
    InterleavePull(Pull(sink)) -> {
      // Store the sink for later
      let interleaver = Interleaver(..interleaver, sink: sink)

      // Check if we have elements available to emit
      case interleaver.current_state {
        // If current is left and we have left elements, emit from left
        Left -> {
          process.send(interleaver.left_source, Pull(interleaver.as_sink))
          actor.continue(interleaver)
        }

        // If current is right and we have right elements, emit from right
        Right -> {
          process.send(interleaver.right_source, Pull(interleaver.as_sink))
          actor.continue(interleaver)
        }
      }
    }
    InterleavePush(Some(element)) -> {
      process.send(interleaver.sink, Some(element))
      case
        interleaver.current_state,
        interleaver.left_done,
        interleaver.right_done
      {
        // the other source is done
        Left, _, True | Right, True, _ -> {
          actor.continue(interleaver)
        }
        Left, _, False -> {
          Interleaver(..interleaver, current_state: Right)
          |> actor.continue
        }
        Right, False, _ -> {
          Interleaver(..interleaver, current_state: Left)
          |> actor.continue
        }
      }
    }

    InterleavePush(None) -> {
      let interleaver = case interleaver.current_state {
        Left -> {
          Interleaver(..interleaver, left_done: True)
        }
        Right -> {
          Interleaver(..interleaver, right_done: True)
        }
      }

      case
        interleaver.current_state,
        interleaver.left_done,
        interleaver.right_done
      {
        // all done
        _, True, True -> {
          process.send(interleaver.sink, None)
          actor.Stop(Normal)
        }
        // swap to right or stay right if left is done
        Left, _, False | Right, True, False -> {
          process.send(interleaver.right_source, Pull(interleaver.as_sink))
          Interleaver(..interleaver, current_state: Right)
          |> actor.continue
        }
        // swap to left or stay left if right is done
        Right, False, _ | Left, False, True -> {
          process.send(interleaver.left_source, Pull(interleaver.as_sink))
          Interleaver(..interleaver, current_state: Left)
          |> actor.continue
        }
      }
    }
  }
}

// -------------------------------
// Try Sink
// -------------------------------
fn start_try_sink(
  source: Subject(Pull(element)),
  initial: acc,
  f: fn(acc, element) -> Result(acc, err),
) -> Result(Subject(Result(acc, err)), StartError) {
  let receiver = process.new_subject()
  actor.Spec(
    init: fn() {
      let self = process.new_subject()
      let selector =
        process.new_selector()
        |> process.selecting(self, function.identity)
      process.send(source, Pull(self))
      TrySink(self, source, initial, f, receiver)
      |> actor.Ready(selector)
    },
    init_timeout: 1000,
    loop: on_try_push,
  )
  |> actor.start_spec
  |> result.map(fn(_) { receiver })
}

// Similar to Sink but with error handling
type TrySink(acc, element, err) {
  TrySink(
    self: Subject(Push(element)),
    source: Subject(Pull(element)),
    accumulator: acc,
    fold: fn(acc, element) -> Result(acc, err),
    receiver: Subject(Result(acc, err)),
  )
}

// Similar to on_push but handles errors
fn on_try_push(message: Push(element), sink: TrySink(acc, element, err)) {
  case message {
    Some(element) -> {
      logging.log(logging.Debug, "try_sink:   " <> string.inspect(element))
      case sink.fold(sink.accumulator, element) {
        Ok(accumulator) -> {
          let sink = TrySink(..sink, accumulator:)
          process.send(sink.source, Pull(sink.self))
          actor.continue(sink)
        }
        Error(err) -> {
          // If we encounter an error, send it to the receiver and stop
          process.send(sink.receiver, Error(err))
          actor.Stop(Normal)
        }
      }
    }
    None -> {
      logging.log(logging.Debug, "try_sink:   None")
      process.send(sink.receiver, Ok(sink.accumulator))
      actor.Stop(Normal)
    }
  }
}
