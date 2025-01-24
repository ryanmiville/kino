//// If you update this file be sure to update the documentation in the actor
//// module which includes a copy of this.

import gleam/dynamic.{type Dynamic}
import gleam/erlang/process
import kino/internal/gen_server.{type From, type GenServer}

pub fn example_test() {
  let assert Ok(srv) = start_link([])
  gen_server.cast(srv, Push("Joe"))
  gen_server.cast(srv, Push("Mike"))
  gen_server.cast(srv, Push("Robert"))

  let assert Ok("Robert") = gen_server.call(srv, Pop, 10)
  let assert Ok("Mike") = gen_server.call(srv, Pop, 10)
  let assert Ok("Joe") = gen_server.call(srv, Pop, 10)

  // The stack is now empty, so if we pop again the actor replies with an error.
  let assert Error(Nil) = gen_server.call(srv, Pop, 10)
  // Lastly, we can send a message to the actor asking it to shut down.
  gen_server.cast(srv, Shutdown)
}

pub type Message(element) {

  Shutdown

  Push(push: element)

  Pop
}

pub fn start_link(
  stack: List(element),
) -> Result(GenServer(Message(element), Result(element, Nil)), Dynamic) {
  gen_server.Spec(init, handle_call, handle_cast, terminate)
  |> gen_server.start_link(stack)
}

fn init(stack: List(element)) -> Result(List(element), Dynamic) {
  Ok(stack)
}

fn handle_call(
  message: Message(element),
  _from: From(Result(element, Nil)),
  state: List(element),
) -> gen_server.Response(Result(element, Nil), List(element)) {
  case message {
    Push(value) -> {
      let new_state = [value, ..state]
      gen_server.Noreply(new_state)
    }

    Pop ->
      case state {
        [] -> {
          gen_server.Reply(Error(Nil), [])
        }

        [first, ..rest] -> {
          gen_server.Reply(Ok(first), rest)
        }
      }

    Shutdown -> gen_server.Stop(process.Normal, state)
  }
}

fn handle_cast(
  message: Message(element),
  state: List(element),
) -> gen_server.Response(Result(element, Nil), List(element)) {
  case message {
    Push(value) -> {
      let new_state = [value, ..state]
      gen_server.Noreply(new_state)
    }

    Pop ->
      case state {
        [] -> {
          gen_server.Noreply([])
        }

        [_, ..rest] -> {
          gen_server.Noreply(rest)
        }
      }

    Shutdown -> gen_server.Stop(process.Normal, state)
  }
}

fn terminate(
  _reason: process.ExitReason,
  _state: List(element),
) -> dynamic.Dynamic {
  dynamic.from(Ok(Nil))
}
