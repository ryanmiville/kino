import gleam/erlang/process.{type Subject, Normal}
import gleam/function
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor.{type StartError}
import gleam/result
import kino/stream/internal/source

type Message(a, b) {
  Left(Option(a))
  Right(Option(b))
  Pull(source.Pull(#(a, b)))
}

type State(a, b) {
  State(
    left_source: Subject(source.Pull(a)),
    right_source: Subject(source.Pull(b)),
    self: Subject(Message(a, b)),
    as_source: Subject(source.Pull(#(a, b))),
    as_left_sink: Subject(Option(a)),
    as_right_sink: Subject(Option(b)),
    left_buffer: List(a),
    right_buffer: List(b),
    sink: Subject(Option(#(a, b))),
  )
}

pub fn start(
  left_source: Subject(source.Pull(a)),
  right_source: Subject(source.Pull(b)),
) -> Result(Subject(source.Pull(#(a, b))), StartError) {
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
        |> process.selecting(as_source, Pull)
        |> process.selecting(as_left_sink, Left)
        |> process.selecting(as_right_sink, Right)

      let zipper =
        State(
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
    loop: on_message,
  )
  |> actor.start_spec
  |> result.map(fn(_) { process.receive_forever(receiver) })
}

fn on_message(message: Message(a, b), zipper: State(a, b)) {
  case message {
    // Handle pull requests from downstream
    Pull(source.Pull(sink)) -> {
      // Store the sink for later
      let zipper = State(..zipper, sink: sink)

      // Try to emit a tuple if we have elements in both buffers
      case zipper.left_buffer, zipper.right_buffer {
        [left, ..left_rest], [right, ..right_rest] -> {
          // We have elements in both buffers, emit a tuple
          process.send(zipper.sink, Some(#(left, right)))

          // Emit with updated buffers
          State(..zipper, left_buffer: left_rest, right_buffer: right_rest)
          |> actor.continue
        }
        _, _ -> {
          // We need more elements, request from sources if buffers are empty
          case zipper.left_buffer {
            [] ->
              process.send(zipper.left_source, source.Pull(zipper.as_left_sink))
            _ -> Nil
          }

          case zipper.right_buffer {
            [] ->
              process.send(
                zipper.right_source,
                source.Pull(zipper.as_right_sink),
              )
            _ -> Nil
          }

          actor.continue(zipper)
        }
      }
    }

    // Handle elements from left source
    Left(Some(element)) -> {
      let zipper =
        State(..zipper, left_buffer: list.append(zipper.left_buffer, [element]))

      // Try to emit if we have elements from both sources
      case zipper.right_buffer {
        [right, ..right_rest] -> {
          case zipper.left_buffer {
            [left, ..left_rest] -> {
              process.send(zipper.sink, Some(#(left, right)))
              State(..zipper, left_buffer: left_rest, right_buffer: right_rest)
              |> actor.continue
            }
            [] -> actor.continue(zipper)
            // This shouldn't happen due to the append above
          }
        }
        [] -> {
          // We need more elements from the right source
          process.send(zipper.right_source, source.Pull(zipper.as_right_sink))
          actor.continue(zipper)
        }
      }
    }

    // Handle elements from right source
    Right(Some(element)) -> {
      let zipper =
        State(
          ..zipper,
          right_buffer: list.append(zipper.right_buffer, [element]),
        )

      // Try to emit if we have elements from both sources
      case zipper.left_buffer {
        [left, ..left_rest] -> {
          case zipper.right_buffer {
            [right, ..right_rest] -> {
              process.send(zipper.sink, Some(#(left, right)))
              State(..zipper, left_buffer: left_rest, right_buffer: right_rest)
              |> actor.continue
            }
            [] -> actor.continue(zipper)
            // This shouldn't happen due to the append above
          }
        }
        [] -> {
          // We need more elements from the left source
          process.send(zipper.left_source, source.Pull(zipper.as_left_sink))
          actor.continue(zipper)
        }
      }
    }

    // Handle end of stream from either source
    Left(None) | Right(None) -> {
      // If either source is done, we're done
      process.send(zipper.sink, None)
      actor.Stop(Normal)
    }
  }
}
