import gleam/erlang/process.{type Subject}
import kino.{type Behavior}
import kino/internal/supervisor as internal
import kino/supervisor

pub fn supervisor_test() {
  let self = process.new_subject()
  let sup = supervisor.start_link(sup(self))

  let assert Ok(first_stack) = process.receive(self, 10)
  kino.send(first_stack, Push("first - hello"))
  kino.send(first_stack, Push("first - world"))
  let assert Ok("first - world") = kino.call(first_stack, Pop, 10)

  let assert Ok(second_stack) =
    supervisor.start_worker_child(sup, worker_spec("2", new_stack_server(self)))

  kino.send(second_stack, Push("second - hello"))

  let assert Ok("first - hello") = kino.call(first_stack, Pop, 10)
  let assert Ok("second - hello") = kino.call(second_stack, Pop, 10)

  let assert Error(Nil) = kino.call(first_stack, Pop, 10)
  let assert Error(Nil) = kino.call(second_stack, Pop, 10)

  kino.send(first_stack, Push("first - will lose"))
  kino.send(first_stack, Shutdown)

  let assert Error(process.CalleeDown(_)) = kino.try_call(first_stack, Pop, 10)

  let assert Ok(restarted) = process.receive(self, 10)
  kino.send(restarted, Push("restarted - hello"))
  let assert Ok("restarted - hello") = kino.call(restarted, Pop, 10)
}

fn sup(subject) {
  use _ref <- supervisor.init

  let worker = new_stack_server(subject)
  supervisor.new(internal.OneForOne)
  |> supervisor.add(worker_spec("1", worker))
}

fn worker_spec(id: String, worker) {
  supervisor.worker_child("stack-" <> id, worker)
}

pub type Message(element) {
  Shutdown
  Push(push: element)
  Pop(reply_to: Subject(Result(element, Nil)))
}

pub fn new_stack_server(subject) -> Behavior(Message(element)) {
  use context <- kino.init()
  process.send(subject, kino.self(context))
  stack_server([])
}

fn stack_server(stack: List(element)) -> Behavior(Message(element)) {
  use _context, message <- kino.receive()
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
      kino.stopped
    }
  }
}