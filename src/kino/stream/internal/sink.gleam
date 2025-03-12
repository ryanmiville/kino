import gleam/erlang/process.{type Subject, Normal}
import gleam/function
import gleam/option.{type Option, None, Some}
import gleam/otp/actor.{type StartError}
import gleam/result
import gleam/string
import kino/stream/internal/source
import logging

type State(acc, element) {
  State(
    self: Subject(Option(element)),
    source: Subject(source.Pull(element)),
    accumulator: acc,
    fold: fn(acc, element) -> acc,
    receiver: Subject(acc),
  )
}

pub fn start(
  source: Subject(source.Pull(element)),
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
      process.send(source, source.Pull(self))
      State(self, source, initial, f, receiver)
      |> actor.Ready(selector)
    },
    init_timeout: 1000,
    loop: on_message,
  )
  |> actor.start_spec
  |> result.map(fn(_) { receiver })
}

fn on_message(message: Option(element), sink: State(acc, element)) {
  case message {
    Some(element) -> {
      logging.log(logging.Debug, "sink:   " <> string.inspect(element))
      let accumulator = sink.fold(sink.accumulator, element)
      let sink = State(..sink, accumulator:)
      process.send(sink.source, source.Pull(sink.self))
      actor.continue(sink)
    }
    None -> {
      logging.log(logging.Debug, "sink:   None")
      process.send(sink.receiver, sink.accumulator)
      actor.Stop(Normal)
    }
  }
}
