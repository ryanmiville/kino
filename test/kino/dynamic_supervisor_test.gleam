import gleam/erlang/process.{type Subject}
import kino/actor.{type ActorRef, type Behavior}
import kino/dynamic_supervisor

pub fn worker_child_test() {
  let self = process.new_subject()
  let assert Ok(sup) = dynamic_supervisor.start_link(dynamic_supervisor())

  let child_spec = new_stack_server(self)
  let assert Ok(first_stack) = dynamic_supervisor.start_child(sup, child_spec)
  let assert Ok(_) = process.receive(self, 10)
  actor.send(first_stack, Push("first - hello"))
  actor.send(first_stack, Push("first - world"))
  let assert Ok("first - world") = actor.call(first_stack, Pop, 10)

  let assert Ok(second_stack) = dynamic_supervisor.start_child(sup, child_spec)
  let assert Ok(_) = process.receive(self, 10)

  actor.send(second_stack, Push("second - hello"))

  let assert Ok("first - hello") = actor.call(first_stack, Pop, 10)
  let assert Ok("second - hello") = actor.call(second_stack, Pop, 10)

  let assert Error(Nil) = actor.call(first_stack, Pop, 10)
  let assert Error(Nil) = actor.call(second_stack, Pop, 10)

  actor.send(first_stack, Push("first - will lose"))
  actor.send(first_stack, Shutdown)

  let assert Error(process.CalleeDown(_)) = actor.try_call(first_stack, Pop, 10)

  let assert Ok(restarted) = process.receive(self, 10)
  actor.send(restarted, Push("restarted - hello"))
  let assert Ok("restarted - hello") = actor.call(restarted, Pop, 10)
}

fn dynamic_supervisor() -> dynamic_supervisor.Spec(ActorRef(a)) {
  use _ <- dynamic_supervisor.init()
  dynamic_supervisor.worker_children(dynamic_supervisor.Permanent)
}

pub type Message(element) {
  Shutdown
  Push(push: element)
  Pop(reply_to: Subject(Result(element, Nil)))
}

pub fn new_stack_server(subject) -> actor.Spec(Message(element)) {
  use self <- actor.init()
  process.send(subject, self)
  stack_server([])
}

fn stack_server(stack: List(element)) -> Behavior(Message(element)) {
  use _, message <- actor.receive()
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
