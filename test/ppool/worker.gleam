import gleam/erlang/process.{type Subject}
import gleam/io
import kino/actor

pub opaque type Message {
  Run
}

pub type State {
  State(task: String, delay: Int, max: Int, reply_to: Subject(String))
}

pub fn spec(state: State) -> actor.Spec(Message) {
  use self <- actor.init()
  actor.send_after(self, state.delay, Run)
  loop(state)
}

fn loop(state: State) -> actor.Behavior(Message) {
  use self, message <- actor.receive()
  case message {
    Run -> {
      process.send(state.reply_to, state.task)
      case state.max {
        max if max <= 1 -> {
          io.println("Task completed: " <> state.task)
          actor.stopped
        }
        max -> {
          actor.send_after(self, state.delay, Run)
          loop(State(..state, max: max - 1))
        }
      }
    }
  }
}
