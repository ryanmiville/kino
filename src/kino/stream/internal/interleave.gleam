import gleam/erlang/process.{type Subject, Normal}
import gleam/function
import gleam/option.{type Option, None, Some}
import gleam/otp/actor.{type StartError}
import gleam/result
import kino/stream/internal/source

type Message(element) {
  InterleavePush(Option(element))
  InterleavePull(source.Pull(element))
}

type Current {
  Left
  Right
}

type State(element) {
  State(
    left_source: Subject(source.Pull(element)),
    right_source: Subject(source.Pull(element)),
    self: Subject(Message(element)),
    as_source: Subject(source.Pull(element)),
    as_sink: Subject(Option(element)),
    current_state: Current,
    // Track which source to pull from next
    sink: Subject(Option(element)),
    left_done: Bool,
    // Track if left source is done
    right_done: Bool,
    // Track if right source is done
  )
}

pub fn start(
  left_source: Subject(source.Pull(element)),
  right_source: Subject(source.Pull(element)),
) -> Result(Subject(source.Pull(element)), StartError) {
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
        State(
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
    loop: on_message,
  )
  |> actor.start_spec
  |> result.map(fn(_) { process.receive_forever(receiver) })
}

fn on_message(message: Message(element), interleaver: State(element)) {
  case message {
    // Handle pull requests from downstream
    InterleavePull(source.Pull(sink)) -> {
      // Store the sink for later
      let interleaver = State(..interleaver, sink: sink)

      // Check if we have elements available to emit
      case interleaver.current_state {
        // If current is left and we have left elements, emit from left
        Left -> {
          process.send(
            interleaver.left_source,
            source.Pull(interleaver.as_sink),
          )
          actor.continue(interleaver)
        }

        // If current is right and we have right elements, emit from right
        Right -> {
          process.send(
            interleaver.right_source,
            source.Pull(interleaver.as_sink),
          )
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
          State(..interleaver, current_state: Right)
          |> actor.continue
        }
        Right, False, _ -> {
          State(..interleaver, current_state: Left)
          |> actor.continue
        }
      }
    }

    InterleavePush(None) -> {
      let interleaver = case interleaver.current_state {
        Left -> {
          State(..interleaver, left_done: True)
        }
        Right -> {
          State(..interleaver, right_done: True)
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
          process.send(
            interleaver.right_source,
            source.Pull(interleaver.as_sink),
          )
          State(..interleaver, current_state: Right)
          |> actor.continue
        }
        // swap to left or stay left if right is done
        Right, False, _ | Left, False, True -> {
          process.send(
            interleaver.left_source,
            source.Pull(interleaver.as_sink),
          )
          State(..interleaver, current_state: Left)
          |> actor.continue
        }
      }
    }
  }
}
