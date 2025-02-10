//// If you update this file be sure to update the documentation in the actor
//// module which includes a copy of this.

import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type Pid}
import gleam/otp/static_supervisor as sup

import gleeunit/should
import kino/server.{type From, type InitResult, type Next, type Server}
import logging

pub fn example_test() {
  // Start the actor with initial state of an empty list, and the
  // `handle_message` callback function (defined below).
  // We assert that it starts successfully.
  //
  // In real-world Gleam OTP programs we would likely write a wrapper functions
  // called `start`, `push` `pop`, `shutdown` to start and interact with the
  // Actor. We are not doing that here for the sake of showing how the Actor
  // API works.
  let assert Ok(srv) = start_link([], atom.create_from_string("example_test"))

  // We can send a message to the actor to push elements onto the stack.
  server.cast(srv, Push("Joe"))
  server.cast(srv, Push("Mike"))
  server.cast(srv, Push("Robert"))

  // The `Push` message expects no response, these messages are sent purely for
  // the side effect of mutating the state held by the actor.
  //
  // We can also send the `Pop` message to take a value off of the actor's
  // stack. This message expects a response, so we use `process.call` to send a
  // message and wait until a reply is received.
  //
  // In this instance we are giving the actor 10 milliseconds to reply, if the
  // `call` function doesn't get a reply within this time it will panic and
  // crash the client process.
  server.call(srv, Pop, 10) |> should.equal(Ok("Robert"))
  server.call(srv, Pop, 10) |> should.equal(Ok("Mike"))
  server.call(srv, Pop, 10) |> should.equal(Ok("Joe"))

  // The stack is now empty, so if we pop again the actor replies with an error.
  server.call(srv, Pop, 10) |> should.equal(Error(Nil))

  // Lastly, we can send a message to the actor asking it to shut down.
  server.stop(srv)
}

pub fn unhandled_message_type_test() {
  logging.set_level(logging.Error)
  let assert Ok(srv) =
    start_link([], atom.create_from_string("unhandled_message_type_test"))
  let assert Ok(pid) = server.owner(srv)
  raw_send(pid, "hello")
  server.cast(srv, Push("Joe"))
  server.call(srv, Pop, 10) |> should.equal(Ok("Joe"))
  server.stop(srv)
  logging.set_level(logging.Info)
}

pub fn restart_test() {
  let self = process.new_subject()
  let assert Ok(_) =
    sup.new(sup.OneForOne)
    |> sup.add(
      sup.worker_child("stack-worker", fn() {
        start_link([], atom.create_from_string("restart_test"))
        |> server.to_supervise_result_ack(self)
      }),
    )
    |> sup.start_link()

  let assert Ok(srv) = process.receive(self, 100)

  server.cast(srv, Push("Joe"))
  server.cast(srv, Push("Mike"))
  server.call(srv, Pop, 10) |> should.equal(Ok("Mike"))

  // stop server
  server.stop(srv)

  // wait for restart
  process.sleep(100)

  server.cast(srv, Push("Robert"))
  server.call(srv, Pop, 10) |> should.equal(Ok("Robert"))
  // restart lost Joe
  server.call(srv, Pop, 10) |> should.equal(Error(Nil))
}

// First step of implementing the stack Actor is to define the message type that
// it can receive.
//
// The type of the elements in the stack is no fixed so a type parameter is used
// for it instead of a concrete type such as `String` or `Int`.
pub type Request(element) {
  // The `Push` message is used to add a new element to the stack.
  // It contains the item to add, the type of which is the `element`
  // parameterised type.
  Push(element)
  // The `Pop` message is used to remove an element from the stack.
  // It contains a `Subject`, which is used to send the response back to the
  // message sender. In this case the reply is of type `Result(element, Nil)`.
  Pop(From(Result(element, Nil)))
}

pub fn start_link(
  stack: List(element),
  name: Atom,
) -> Result(Server(Request(element)), Dynamic) {
  server.new(init, handler)
  |> server.name(name)
  |> server.start_link(stack)
}

fn init(stack: List(element)) -> InitResult(List(element)) {
  server.Ready(stack)
}

// The last part is to implement the `handle_message` callback function.
//
// This function is called by the Actor each for each message it receives.
// Actor is single threaded only does one thing at a time, so it handles
// messages sequentially and one at a time, in the order they are received.
//
// The function takes the message and the current state, and returns a data
// structure that indicates what to do next, along with the new state.
fn handler(
  _self: Server(request),
  request: Request(element),
  state: List(element),
) -> Next(List(element)) {
  case request {
    // For the `Push` message we add the new element to the stack and return
    // `actor.Continue` with this new stack, causing the actor to process any
    // queued messages or wait for more.
    Push(element) -> server.continue([element, ..state])

    // For the `Pop` message we attempt to remove an element from the stack,
    // sending it or an error back to the caller, before continuing.
    Pop(from) ->
      case state {
        // When the stack is empty we can't pop an element, so we send an
        // error back.
        [] -> {
          server.reply(from, Error(Nil))
          server.continue(state)
        }
        // Otherwise we send the first element back and use the remaining
        // elements as the new state.
        [first, ..rest] -> {
          server.reply(from, Ok(first))
          server.continue(rest)
        }
      }
  }
}

@external(erlang, "erlang", "send")
fn raw_send(a: Pid, b: anything) -> anything
