import gleam/bool
import gleam/erlang/process.{type Subject, Normal}
import gleam/function
import gleam/option.{type Option, None, Some}
import gleam/otp/actor.{type StartError}
import gleam/result
import kino/stream/internal/action.{type Action, Continue, Emit, Stop}
import kino/stream/internal/source

type Message(in, out) {
  Push(Option(in))
  Pull(source.Pull(out))
}

type State(in, out) {
  State(
    self: Subject(Message(in, out)),
    as_sink: Subject(Option(in)),
    as_source: Subject(source.Pull(out)),
    sources: List(Subject(source.Pull(in))),
    sink: Subject(Option(out)),
    process: fn(in) -> Action(in, out),
  )
}

pub fn start(
  sources: List(Subject(source.Pull(in))),
  process: fn(in) -> Action(in, out),
) -> Result(Subject(source.Pull(out)), StartError) {
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
        |> process.selecting(as_source, Pull)
        |> process.selecting(as_sink, Push)
      let flow =
        State(
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

fn on_message(message: Message(in, out), flow: State(in, out)) {
  use <- bool.lazy_guard(flow.sources == [], fn() { actor.Stop(Normal) })
  let assert [source, ..sources] = flow.sources
  case message {
    Push(Some(element)) -> {
      case flow.process(element) {
        Continue(process) -> {
          process.send(source, source.Pull(flow.as_sink))
          actor.continue(State(..flow, process:))
        }
        Emit(element, process) -> {
          process.send(flow.sink, Some(element))
          let flow = State(..flow, process:)
          actor.continue(flow)
        }
        Stop -> {
          process.send(flow.sink, None)
          actor.Stop(Normal)
        }
      }
    }
    Push(None) -> {
      case sources {
        [] -> {
          process.send(flow.sink, None)
          actor.Stop(Normal)
        }
        _ -> {
          process.send(flow.as_source, source.Pull(flow.sink))
          State(..flow, sources:) |> actor.continue
        }
      }
    }
    Pull(source.Pull(sink)) -> {
      process.send(source, source.Pull(flow.as_sink))
      State(..flow, sink:) |> actor.continue
    }
  }
}
