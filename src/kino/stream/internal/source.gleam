import gleam/erlang/process.{type Subject, Normal}
import gleam/function
import gleam/option.{type Option, None, Some}
import gleam/otp/actor.{type StartError}
import kino/stream/internal/action.{type Action, Continue, Emit, Stop}

pub type Pull(element) {
  Pull(reply_to: Subject(Option(element)))
}

type State(element) {
  State(self: Subject(Pull(element)), emit: fn(Nil) -> Action(Nil, element))
}

pub fn start(
  emit: fn(Nil) -> Action(Nil, element),
) -> Result(Subject(Pull(element)), StartError) {
  actor.Spec(
    init: fn() {
      let self = process.new_subject()
      let selector =
        process.new_selector()
        |> process.selecting(self, function.identity)
      State(self:, emit:)
      |> actor.Ready(selector)
    },
    init_timeout: 1000,
    loop: on_message,
  )
  |> actor.start_spec
}

fn on_message(message: Pull(element), source: State(element)) {
  case source.emit(Nil) {
    Emit(chunk, emit) -> {
      process.send(message.reply_to, Some(chunk))
      State(..source, emit:) |> actor.continue
    }
    Continue(emit) -> {
      process.send(source.self, message)
      State(..source, emit:) |> actor.continue
    }
    Stop -> {
      process.send(message.reply_to, None)
      actor.Stop(Normal)
    }
  }
}
