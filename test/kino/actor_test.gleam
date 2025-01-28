import gleam/erlang/process.{type Subject}

// import kino.{type ActorRef, type Behavior, type Spec}
import kino/actor.{type Behavior, type Spec}

// pub fn main() {
//   gleeunit.main()
// }

pub fn actor_test() {
  let assert Ok(stack) = start_link()
  actor.send(stack, Push("Joe"))
  actor.send(stack, Push("Mike"))
  actor.send(stack, Push("Robert"))

  let assert Ok(Ok("Robert")) = actor.try_call(stack, Pop, 10)
  let assert Ok(Ok("Mike")) = actor.try_call(stack, Pop, 10)
  let assert Ok(Ok("Joe")) = actor.try_call(stack, Pop, 10)

  // The stack is now empty, so if we pop again the actor replies with an error.
  let assert Ok(Error(Nil)) = actor.try_call(stack, Pop, 10)
  // Lastly, we can send a message to the actor asking it to shut down.
  actor.send(stack, Shutdown)
}

pub type Message(element) {

  Shutdown

  Push(push: element)

  Pop(reply_to: Subject(Result(element, Nil)))
}

pub fn new_stack_server() -> Spec(Message(element)) {
  use _self <- actor.init()
  stack_server([])
}

fn stack_server(stack: List(element)) -> Behavior(Message(element)) {
  use _self, message <- actor.receive()
  case message {
    Push(value) -> {
      let new_stack = [value, ..stack]
      stack_server(new_stack)
    }

    Pop(reply_to:) -> {
      case stack {
        [] -> {
          process.send(reply_to, Error(Nil))
          stack_server(stack)
        }

        [first, ..rest] -> {
          process.send(reply_to, Ok(first))
          stack_server(rest)
        }
      }
    }

    Shutdown -> {
      actor.stopped
    }
  }
}

pub fn start_link() {
  actor.start_link(new_stack_server())
}
