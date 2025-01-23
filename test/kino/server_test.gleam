//// If you update this file be sure to update the documentation in the actor
//// module which includes a copy of this.

import gleam/dynamic.{type Dynamic}
import gleam/erlang/process
import kino/server.{type From, type Server}

pub fn example_test() {
  let assert Ok(srv) = start_link([])
  server.cast(srv, Push("Joe"))
  server.cast(srv, Push("Mike"))
  server.cast(srv, Push("Robert"))

  let assert Ok("Robert") = server.call(srv, Pop, 10)
  let assert Ok("Mike") = server.call(srv, Pop, 10)
  let assert Ok("Joe") = server.call(srv, Pop, 10)

  // The stack is now empty, so if we pop again the actor replies with an error.
  let assert Error(Nil) = server.call(srv, Pop, 10)
  // Lastly, we can send a message to the actor asking it to shut down.
  server.cast(srv, Shutdown)
}

pub type Message(element) {

  Shutdown

  Push(push: element)

  Pop
}

pub fn start_link(
  stack: List(element),
) -> Result(Server(Message(element), Result(element, Nil)), Dynamic) {
  server.Spec(init, handle_call, handle_cast, terminate)
  |> server.start_link(stack)
}

fn init(stack: List(element)) -> Result(List(element), Dynamic) {
  Ok(stack)
}

fn handle_call(
  message: Message(element),
  _from: From(Result(element, Nil)),
  state: List(element),
) -> server.Response(Result(element, Nil), List(element)) {
  case message {
    Push(value) -> {
      let new_state = [value, ..state]
      server.Noreply(new_state)
    }

    Pop ->
      case state {
        [] -> {
          server.Reply(Error(Nil), [])
        }

        [first, ..rest] -> {
          server.Reply(Ok(first), rest)
        }
      }

    Shutdown -> server.Stop(process.Normal, state)
  }
}

fn handle_cast(
  message: Message(element),
  state: List(element),
) -> server.Response(Result(element, Nil), List(element)) {
  case message {
    Push(value) -> {
      let new_state = [value, ..state]
      server.Noreply(new_state)
    }

    Pop ->
      case state {
        [] -> {
          server.Noreply([])
        }

        [_, ..rest] -> {
          server.Noreply(rest)
        }
      }

    Shutdown -> server.Stop(process.Normal, state)
  }
}

fn terminate(
  _reason: process.ExitReason,
  _state: List(element),
) -> dynamic.Dynamic {
  dynamic.from(Ok(Nil))
}
