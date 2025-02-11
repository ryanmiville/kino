//// If you update this file be sure to update the documentation in the gen_server
//// module which includes a copy of this.

import kino/gen_server.{type From, type GenServer, type InitResult, type Next}

pub fn example_test() {
  // Start the GenServer with the `init` and
  // `handler` callback functions (defined below).
  // We assert that it starts successfully.
  //
  // In real-world programs we would likely write a wrapper functions
  // called `start_link`, `push`, `pop`, `stop` to start and interact with the
  // GenServer. We are not doing that here for the sake of showing how the GenServer
  // API works.
  let assert Ok(srv) =
    gen_server.new(init, handler)
    |> gen_server.start_link([])

  // We can send a message to the server to push elements onto the stack.
  gen_server.cast(srv, Push("Joe"))
  gen_server.cast(srv, Push("Mike"))
  gen_server.cast(srv, Push("Robert"))

  // The `Push` message expects no response, these messages are sent purely for
  // the side effect of mutating the state held by the server.
  //
  // We can also send the `Pop` message to take a value off of the server's
  // stack. This message expects a response, so we use `gen_server.call` to send a
  // message and wait until a reply is received.
  //
  // In this instance we are giving the server 10 milliseconds to reply, if the
  // `call` function doesn't get a reply within this time it will panic and
  // crash the client process.
  let assert Ok("Robert") = gen_server.call(srv, Pop, 10)
  let assert Ok("Mike") = gen_server.call(srv, Pop, 10)
  let assert Ok("Joe") = gen_server.call(srv, Pop, 10)

  // The stack is now empty, so if we pop again the server replies with an error.
  let assert Error(Nil) = gen_server.call(srv, Pop, 10)

  // Lastly, we can stop the server.
  gen_server.stop(srv)
}

// First step of implementing the stack GenServer is to define the message type that
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
  // It contains a `From`, which is used to send the response back to the
  // message sender. In this case the reply is of type `Result(element, Nil)`.
  Pop(From(Result(element, Nil)))
}

// The init callback function is called when the GenServer starts up. It is
// responsible for setting the initial state of the server.
fn init(stack: List(element)) -> InitResult(List(element)) {
  gen_server.Ready(stack)
}

// The last part is to implement the `handler` callback function.
//
// This function is called by the GenServer for each message it receives.
// GenServer is single threaded, so it handles messages one at a time, in the
// order they are received.
//
// The function takes a reference to the GenServer, the request, and the current
// state, and returns a data structure that indicates what to do next,
// along with the new state.
fn handler(
  _self: GenServer(request),
  request: Request(element),
  state: List(element),
) -> Next(List(element)) {
  case request {
    // For the `Push` message we add the new element to the stack and return
    // `gen_server.continue` with this new stack, causing the actor to process any
    // queued messages or wait for more.
    Push(element) -> gen_server.continue([element, ..state])

    // For the `Pop` message we attempt to remove an element from the stack,
    // sending it or an error back to the caller, before continuing.
    Pop(from) ->
      case state {
        // When the stack is empty we can't pop an element, so we send an
        // error back.
        [] -> {
          gen_server.reply(from, Error(Nil))
          gen_server.continue(state)
        }
        // Otherwise we send the first element back and use the remaining
        // elements as the new state.
        [first, ..rest] -> {
          gen_server.reply(from, Ok(first))
          gen_server.continue(rest)
        }
      }
  }
}
