import gleam/bool
import gleam/erlang/process.{type Subject, Normal}
import gleam/function
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor.{type StartError}
import gleam/result.{try}
import gleam/string
import logging

const default_chunk_size = 5

type Emit(element) {
  Continue(chunk: List(element), fn() -> Emit(element))
  Stop
}

type Start(a) =
  Result(a, StartError)

pub opaque type Stream(element) {
  Stream(start: fn() -> Start(Subject(Pull(element))))
}

pub type Step(element, state) {
  Next(element: List(element), state: state)
  Done
}

pub fn empty() -> Stream(element) {
  from_emit(fn() { Stop })
}

fn from_emit(emit: fn() -> Emit(element)) -> Stream(element) {
  Stream(fn() { start_source(emit) })
}

pub fn from_list(chunk: List(element)) -> Stream(element) {
  let chunks = list.sized_chunk(chunk, default_chunk_size)
  let f = fn(state) {
    case state {
      [] -> Done
      [next, ..rest] -> Next(next, rest)
    }
  }
  unfold(chunks, f)
}

pub fn single(value: element) -> Stream(element) {
  from_list([value])
}

pub fn repeatedly(f: fn() -> element) -> Stream(element) {
  unfold(Nil, fn(_) { Next([f()], Nil) })
}

pub fn repeat(x: element) -> Stream(element) {
  repeatedly(fn() { x })
}

pub fn unfold(
  initial: state,
  f: fn(state) -> Step(element, state),
) -> Stream(element) {
  from_emit(do_unfold(initial, f))
}

fn do_unfold(
  initial: state,
  f: fn(state) -> Step(element, state),
) -> fn() -> Emit(element) {
  fn() {
    case f(initial) {
      Next(elements, state) -> Continue(elements, do_unfold(state, f))
      Done -> Stop
    }
  }
}

pub fn take(stream: Stream(element), take: Int) -> Stream(element) {
  use <- bool.lazy_guard(take <= 0, empty)
  fn() {
    let process = fn(count, elements) {
      use <- bool.guard(count <= 0, Done)
      let #(count, elements) = do_take(count, elements, [])
      Next(list.reverse(elements), count)
    }
    use source <- try(stream.start())
    use #(as_source, _) <- try(start_flow(source, take, process))
    Ok(as_source)
  }
  |> Stream
}

fn do_take(count: Int, elements: List(a), acc: List(a)) -> #(Int, List(a)) {
  case count, elements {
    0, _ | _, [] -> #(count, acc)
    _, [first, ..rest] -> do_take(count - 1, rest, [first, ..acc])
  }
}

// pub fn rechunk(stream: Stream(element), chunk_size: Int) -> Stream(element) {
//   todo
// }

pub fn map_chunks(stream: Stream(a), f: fn(List(a)) -> List(b)) -> Stream(b) {
  fn() {
    let process = fn(state, elements: List(a)) -> Step(b, state) {
      Next(f(elements), state)
    }
    use source <- try(stream.start())
    use #(as_source, _) <- try(start_flow(source, Nil, process))
    Ok(as_source)
  }
  |> Stream
}

pub fn map(stream: Stream(a), f: fn(a) -> b) -> Stream(b) {
  map_chunks(stream, list.map(_, f))
}

pub fn filter(stream: Stream(a), f: fn(a) -> Bool) -> Stream(a) {
  map_chunks(stream, list.filter(_, f))
}

// pub fn flatten(stream: Stream(Stream(element))) -> Stream(element) {
//   todo
//   // map_chunks(stream, list.flatten)
// }

pub fn fold_chunks(
  stream: Stream(element),
  initial: acc,
  f: fn(acc, List(element)) -> acc,
) -> Result(acc, StartError) {
  use source <- try(stream.start())
  use subject <- result.map(start_sink(source, initial, f))
  process.receive_forever(subject)
}

pub fn to_list(stream: Stream(element)) -> Result(List(element), StartError) {
  to_chunks(stream)
  |> result.map(list.flatten)
}

pub fn to_chunks(
  stream: Stream(element),
) -> Result(List(List(element)), StartError) {
  let f = fn(acc, chunk) -> List(List(element)) { [chunk, ..acc] }
  fold_chunks(stream, [], f) |> result.map(list.reverse)
}

// -------------------------------
// Source
// -------------------------------
type Pull(element) {
  Pull(reply_to: Subject(Option(List(element))))
}

type Source(element) {
  Source(self: Subject(Pull(element)), emit: fn() -> Emit(element))
}

fn start_source(emit: fn() -> Emit(element)) -> Start(Subject(Pull(element))) {
  actor.Spec(
    init: fn() {
      let self = process.new_subject()
      let selector =
        process.new_selector()
        |> process.selecting(self, function.identity)
      Source(self:, emit:)
      |> actor.Ready(selector)
    },
    init_timeout: 1000,
    loop: on_pull,
  )
  |> actor.start_spec
}

fn on_pull(message: Pull(element), source: Source(element)) {
  case source.emit() {
    Continue(chunk, emit) -> {
      logging.log(logging.Debug, "source: " <> string.inspect(chunk))
      process.send(message.reply_to, Some(chunk))
      Source(..source, emit:) |> actor.continue
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
  Option(List(element))

type Sink(acc, element) {
  Sink(
    self: Subject(Push(element)),
    source: Subject(Pull(element)),
    accumulator: acc,
    fold: fn(acc, List(element)) -> acc,
    receiver: Subject(acc),
  )
}

fn start_sink(
  source: Subject(Pull(element)),
  initial: acc,
  f: fn(acc, List(element)) -> acc,
) -> Start(Subject(acc)) {
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
    Some(elements) -> {
      logging.log(logging.Debug, "sink:   " <> string.inspect(elements))
      let accumulator = sink.fold(sink.accumulator, elements)
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

type Flow(state, in, out) {
  Flow(
    self: Subject(Message(in, out)),
    as_sink: Subject(Push(in)),
    as_source: Subject(Pull(out)),
    source: Subject(Pull(in)),
    sink: Subject(Push(out)),
    state: state,
    process: fn(state, List(in)) -> Step(out, state),
  )
}

fn start_flow(
  source: Subject(Pull(in)),
  state: state,
  process: fn(state, List(in)) -> Step(out, state),
) -> Start(#(Subject(Pull(out)), Subject(Push(in)))) {
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
          source:,
          sink: dummy,
          state:,
          process:,
        )
      process.send(receiver, #(as_source, as_sink))
      actor.Ready(flow, selector)
    },
    init_timeout: 1000,
    loop: on_message,
  )
  |> actor.start_spec
  |> result.map(fn(_) { process.receive_forever(receiver) })
}

fn on_message(message: Message(in, out), flow: Flow(state, in, out)) {
  process.sleep(250)
  case message {
    FlowPush(Some(elements)) -> {
      let before = string.inspect(elements)
      case flow.process(flow.state, elements) {
        Next(elements, state) -> {
          logging.log(
            logging.Debug,
            "flow:   " <> before <> " -> " <> string.inspect(elements),
          )
          process.send(flow.sink, Some(elements))
          let flow = Flow(..flow, state:)
          actor.continue(flow)
        }
        Done -> {
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

pub fn main() {
  logging.configure()
  logging.set_level(logging.Debug)
  io.println("====Doubler====")
  let assert Ok([2, 4, 6]) =
    from_list([1, 2, 3]) |> map(int.multiply(_, 2)) |> to_list

  process.sleep(100)

  io.println("====Counter====")
  let counter = unfold(0, fn(acc) { Next([acc], acc + 1) })
  let assert Ok([0, 1, 2]) = counter |> take(3) |> to_list
  process.sleep(100)
}
