import gleam/erlang/process.{type Subject, Normal}
import gleam/function
import gleam/option.{type Option, None, Some}
import gleam/otp/actor.{type StartError}
import gleam/result
import kino/stream/internal/source

type Starter(a) =
  fn() -> Result(Subject(source.Pull(a)), StartError)

type Message(a) {
  SourcePush(Option(Starter(a)))
  Push(Option(a))
  Pull(source.Pull(a))
}

type State(a) {
  State(
    initial: Subject(source.Pull(Starter(a))),
    current: Option(Subject(source.Pull(a))),
    self: Subject(Message(a)),
    as_source: Subject(source.Pull(a)),
    as_sink: Subject(Option(a)),
    as_stream_sink: Subject(Option(Starter(a))),
    waiting: Bool,
    sink: Subject(Option(a)),
  )
}

pub fn start(
  source: Subject(source.Pull(Starter(a))),
) -> Result(Subject(source.Pull(a)), StartError) {
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
        |> process.selecting(as_source, Pull)
        |> process.selecting(as_sink, Push)
        |> process.selecting(as_stream_sink, SourcePush)
      let flow =
        State(
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
    loop: on_message,
  )
  |> actor.start_spec
  |> result.map(fn(_) { process.receive_forever(receiver) })
}

fn on_message(message: Message(a), flow: State(a)) {
  case message {
    SourcePush(None) -> {
      process.send(flow.sink, None)
      actor.Stop(Normal)
    }
    SourcePush(Some(stream)) -> {
      // TODO
      let assert Ok(source) = stream()
      process.send(source, source.Pull(flow.as_sink))
      State(..flow, current: Some(source))
      |> actor.continue
    }
    Push(Some(element)) -> {
      process.send(flow.sink, Some(element))
      actor.continue(flow)
    }
    Push(None) -> {
      process.send(flow.initial, source.Pull(flow.as_stream_sink))
      State(..flow, waiting: True, current: None)
      |> actor.continue
    }
    Pull(source.Pull(sink)) -> {
      case flow.current {
        Some(source) -> {
          process.send(source, source.Pull(flow.as_sink))
          State(..flow, sink:)
          |> actor.continue
        }
        None -> {
          case flow.waiting {
            True -> actor.continue(flow)
            False -> {
              process.send(flow.initial, source.Pull(flow.as_stream_sink))
              State(..flow, waiting: True, current: None, sink:)
              |> actor.continue
            }
          }
        }
      }
    }
  }
}
