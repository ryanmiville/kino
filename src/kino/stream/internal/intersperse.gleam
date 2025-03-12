import gleam/erlang/process.{type Subject, Normal}
import gleam/function
import gleam/option.{type Option, None, Some}
import gleam/otp/actor.{type StartError}
import gleam/result
import kino/stream/internal/source

type Message(element) {
  Push(Option(element))
  Pull(source.Pull(element))
}

type Next(element) {
  ElementNext
  // Waiting for next element from source
  SeparatorNext
  // Ready to insert separator before next element
}

type State(element) {
  State(
    source: Subject(source.Pull(element)),
    self: Subject(Message(element)),
    as_source: Subject(source.Pull(element)),
    as_sink: Subject(Option(element)),
    sink: Subject(Option(element)),
    separator: element,
    state: Next(element),
    // Holds the next element to emit after separator
  )
}

pub fn start(
  source: Subject(source.Pull(element)),
  separator: element,
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
        |> process.selecting(as_source, Pull)
        |> process.selecting(as_sink, Push)

      let intersperser =
        State(
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
    loop: on_message,
  )
  |> actor.start_spec
  |> result.map(fn(_) { process.receive_forever(receiver) })
}

fn on_message(message: Message(element), intersperser: State(element)) {
  case message {
    // Handle pull requests from downstream
    Pull(source.Pull(sink)) -> {
      let intersperser = State(..intersperser, sink: sink)

      case intersperser.state {
        // Initial state or need element - request one from source
        ElementNext -> {
          process.send(intersperser.source, source.Pull(intersperser.as_sink))
          actor.continue(intersperser)
        }

        // Ready to insert separator and have next element
        SeparatorNext -> {
          // Send separator first
          process.send(intersperser.sink, Some(intersperser.separator))

          // Next time we'll send the element we're holding
          State(..intersperser, state: ElementNext)
          |> actor.continue
        }
      }
    }

    // Handle elements from source
    Push(Some(element)) -> {
      case intersperser.state {
        // First element, emit directly
        // Initial -> {
        //   process.send(intersperser.sink, Some(element))
        //   State(..intersperser, state: SeparatorNext, next_element: None)
        //   |> actor.continue
        // }
        // Need element - this means we previously sent the separator
        ElementNext -> {
          // Send the element we were holding from before
          process.send(intersperser.sink, Some(element))

          // Next we'll need to insert separator
          State(..intersperser, state: SeparatorNext)
          |> actor.continue
        }

        // this shouldn't happen
        SeparatorNext -> {
          actor.continue(intersperser)
        }
      }
    }

    // Handle end of stream
    Push(None) -> {
      // Signal end of stream downstream
      process.send(intersperser.sink, None)
      actor.Stop(Normal)
    }
  }
}
