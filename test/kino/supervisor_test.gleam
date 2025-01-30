import gleam/erlang/process.{type Subject}
import kino/actor.{type Behavior}
import kino/supervisor

pub fn supervisor_test() {
  let self = process.new_subject()
  let assert Ok(sup) = supervisor.start_link(sup(self))

  let assert Ok(first_stack) = process.receive(self, 10)
  actor.send(first_stack, Push("first - hello"))
  actor.send(first_stack, Push("first - world"))
  let assert Ok("first - world") = actor.call(first_stack, Pop, 10)

  let assert Ok(second_stack) =
    supervisor.start_child(
      sup,
      supervisor.worker_child("stack-2", new_stack_server(self)),
    )

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

fn sup(subject) -> supervisor.Spec {
  use _ <- supervisor.init()

  let worker = supervisor.worker_child("stack-1", new_stack_server(subject))

  supervisor.new(supervisor.OneForOne) |> supervisor.add_child(worker)
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
