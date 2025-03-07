import gleam/erlang/process.{type Subject}
import gleam/function
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor.{type StartError}
import gleam/result
import logging

// type Loop(state, element) {
//   Continue(state: state, chunk: List(element))
//   Done(chunk: List(element))
// }

type Emit(element) {
  Continue(chunk: List(element), fn() -> Emit(element))
  Stop
}

pub opaque type Stream(element) {
  Stream(emit: fn() -> Emit(element))
}

pub type Step(element, state) {
  Next(element: List(element), state: state)
  Done
}

pub fn from_list(chunk: List(element)) -> Stream(element) {
  Stream(fn() { Continue(chunk, fn() { Stop }) })
}

pub fn single(value: element) -> Stream(element) {
  from_list([value])
}

pub fn unfold(
  initial: state,
  f: fn(state) -> Step(element, state),
) -> Stream(element) {
  Stream(unfold_loop(initial, f))
}

fn unfold_loop(
  initial: state,
  f: fn(state) -> Step(element, state),
) -> fn() -> Emit(element) {
  fn() {
    case f(initial) {
      Next(elements, state) -> Continue(elements, unfold_loop(state, f))
      Done -> Stop
    }
  }
}

pub fn fold_chunks(
  stream: Stream(element),
  initial: acc,
  f: fn(acc, List(element)) -> acc,
) -> Result(acc, StartError) {
  use source <- result.try(new_source(stream))
  use receiver <- result.map(new_sink(source, initial, f))
  process.receive_forever(receiver)
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

type Pull(element) {
  Pull(reply_to: Subject(Option(List(element))))
}

type Source(element) {
  Source(self: Subject(Pull(element)), emit: fn() -> Emit(element))
}

fn new_source(
  stream: Stream(element),
) -> Result(Subject(Pull(element)), StartError) {
  actor.Spec(
    init: fn() {
      let self = process.new_subject()
      let selector =
        process.new_selector()
        |> process.selecting(self, function.identity)
      Source(self, stream.emit)
      |> actor.Ready(selector)
    },
    init_timeout: 1000,
    loop: pull,
  )
  |> actor.start_spec
}

fn pull(message: Pull(element), source: Source(element)) {
  case source.emit() {
    Continue(chunk, emit) -> {
      process.send(message.reply_to, Some(chunk))
      Source(..source, emit:) |> actor.continue
    }
    Stop -> {
      process.send(message.reply_to, None)
      actor.Stop(process.Normal)
    }
  }
}

fn new_sink(
  source: Subject(Pull(element)),
  initial: acc,
  f: fn(acc, List(element)) -> acc,
) {
  let receiver = process.new_subject()
  actor.Spec(
    init: fn() {
      let self = process.new_subject()
      let selector =
        process.new_selector()
        |> process.selecting(self, function.identity)
      Sink(self, source, initial, f, receiver)
      |> actor.Ready(selector)
    },
    init_timeout: 1000,
    loop: consume,
  )
  |> actor.start_spec
  |> result.map(fn(_) { receiver })
}

type Sink(acc, element) {
  Sink(
    self: Subject(Option(List(element))),
    source: Subject(Pull(element)),
    accumulator: acc,
    fold: fn(acc, List(element)) -> acc,
    receiver: Subject(acc),
  )
}

fn consume(message: Option(List(element)), sink: Sink(acc, element)) {
  case message {
    Some(elements) -> {
      let accumulator = sink.fold(sink.accumulator, elements)
      let sink = Sink(..sink, accumulator:)
      process.send(sink.source, Pull(sink.self))
      actor.continue(sink)
    }
    None -> {
      process.send(sink.receiver, sink.accumulator)
      actor.Stop(process.Normal)
    }
  }
}

pub fn main() {
  logging.configure()
  logging.set_level(logging.Debug)
  let assert Ok([1]) = single(1) |> to_list
  let assert Ok([1, 2, 3]) = from_list([1, 2, 3]) |> to_list
}
