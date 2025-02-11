//// Bindings to Erlang/OTP's `gen_server` module.
////
//// For further detail see the Erlang documentation:
//// <https://www.erlang.org/doc/apps/stdlib/gen_server.html>.
////
//// ## Example
////
//// ```gleam
//// pub fn main() {
////   // Start the GenServer with the `init` and
////   // `handler` callback functions (defined below).
////   // We assert that it starts successfully.
////   //
////   // In real-world programs we would likely write a wrapper functions
////   // called `start_link`, `push`, `pop`, `stop` to start and interact with the
////   // GenServer. We are not doing that here for the sake of showing how the GenServer
////   // API works.
////   let assert Ok(srv) =
////     gen_server.new(init, handler)
////     |> gen_server.start_link([])
////
////   // We can send a request to the server to push elements onto the stack.
////   gen_server.cast(srv, Push("Joe"))
////   gen_server.cast(srv, Push("Mike"))
////   gen_server.cast(srv, Push("Robert"))
////
////   // The `Push` message expects no response, these messages are sent purely for
////   // the side effect of mutating the state held by the server.
////   //
////   // We can also send the `Pop` message to take a value off of the server's
////   // stack. This message expects a response, so we use `gen_server.call` to send a
////   // message and wait until a reply is received.
////   //
////   // In this instance we are giving the server 10 milliseconds to reply, if the
////   // `call` function doesn't get a reply within this time it will panic and
////   // crash the client process.
////   let assert Ok("Robert") = gen_server.call(srv, Pop, 10)
////   let assert Ok("Mike") = gen_server.call(srv, Pop, 10)
////   let assert Ok("Joe") = gen_server.call(srv, Pop, 10)
////
////   // The stack is now empty, so if we pop again the server replies with an error.
////   let assert Error(Nil) = gen_server.call(srv, Pop, 10)
////
////   // Lastly, we can stop the server.
////   gen_server.stop(srv)
//// }
//// ```
////
//// Here is the code that is used to implement this gen_server:
////
//// ```gleam
//// import kino/gen_server.{type From, type GenServer, type InitResult, type Next}
////
//// // First step of implementing the stack GenServer is to define the message type that
//// // it can receive.
//// //
//// // The type of the elements in the stack is no fixed so a type parameter is used
//// // for it instead of a concrete type such as `String` or `Int`.
//// pub type Request(element) {
////   // The `Push` message is used to add a new element to the stack.
////   // It contains the item to add, the type of which is the `element`
////   // parameterised type.
////   Push(element)
////   // The `Pop` message is used to remove an element from the stack.
////   // It contains a `From`, which is used to send the response back to the
////   // message sender. In this case the reply is of type `Result(element, Nil)`.
////   Pop(From(Result(element, Nil)))
//// }
////
//// // The init callback function is called when the GenServer starts up. It is
//// // responsible for setting the initial state of the server.
//// fn init(stack: List(element)) -> InitResult(List(element)) {
////   gen_server.Ready(stack)
//// }
////
//// // The last part is to implement the `handler` callback function.
//// //
//// // This function is called by the GenServer for each message it receives.
//// // GenServer is single threaded, so it handles messages one at a time, in the
//// // order they are received.
//// //
//// // The function takes a reference to the GenServer, the request, and the current
//// // state, and returns a data structure that indicates what to do next,
//// // along with the new state.
//// fn handler(
////   _self: GenServer(request),
////   request: Request(element),
////   state: List(element),
//// ) -> Next(List(element)) {
////   case request {
////     // For the `Push` message we add the new element to the stack and return
////     // `gen_server.continue` with this new stack, causing the server to
////     // process any queued messages or wait for more.
////     Push(element) -> gen_server.continue([element, ..state])
////
////     // For the `Pop` message we attempt to remove an element from the stack,
////     // sending it or an error back to the caller, before continuing.
////     Pop(from) ->
////       case state {
////         // When the stack is empty we can't pop an element, so we send an
////         // error back.
////         [] -> {
////           gen_server.reply(from, Error(Nil))
////           gen_server.continue(state)
////         }
////         // Otherwise we send the first element back and use the remaining
////         // elements as the new state.
////         [first, ..rest] -> {
////           gen_server.reply(from, Ok(first))
////           gen_server.continue(rest)
////         }
////       }
////   }
//// }
//// ```

//

import gleam/dynamic.{type Dynamic}
import gleam/erlang.{type Reference}
import gleam/erlang/atom.{type Atom}
import gleam/erlang/charlist.{type Charlist}
import gleam/erlang/process.{type ExitReason, type Pid}
import gleam/option.{type Option, None, Some}
import gleam/otp/static_supervisor
import gleam/result
import gleam/string
import kino/internal/gen_server

/// A reference to a GenServer process that can accept messages of type
/// `request`. If the server was named, the reference is still valid if the
/// process is restarted.
pub opaque type GenServer(request) {
  PidRef(Pid)
  NameRef(Atom)
}

/// The result of a GenServer's `init` callback function.
pub type InitResult(state) {
  /// The server has started successfully and is ready to accept requests.
  Ready(state: state)

  /// The server has started successfully and is ready to accept requests.
  /// A timeout occurs unless a request or a message is received within that many milliseconds.
  /// Timeouts can be handled by implementing the `handle_timeout` callback function.
  Timeout(state: state, timeout: Int)

  /// The server failed to initialize. The process exists with the given reason.
  Failed(reason: Dynamic)
}

/// The type that represents the sender of a request. A request must include a `From` field to be used by `call`.
///
pub type From(reply)

/// The type used to indicate what to do after handling a request.
///
pub opaque type Next(state) {
  Continue(state: state, timeout: Option(Int))
  Stop(state: state, reason: ExitReason)
}

/// A message received when a monitored process exits.
///
pub type ProcessDown {
  ProcessDown(pid: Pid, ref: Reference, reason: Dynamic)
}

/// Continue handling requests with the updated state.
///
pub fn continue(state: state) -> Next(state) {
  Continue(state, None)
}

/// Provide a timeout for the that begins after the current request is handled.
/// A timeout occurs unless a request or a message is received within that many milliseconds.
/// Timeouts can be handled by implementing the `handle_timeout` callback function.
pub fn with_timeout(next: Next(state), timeout: Int) -> Next(state) {
  case next {
    Continue(state, _) -> Continue(state, Some(timeout))
    _ -> next
  }
}

/// This data structure holds all the values to describe a GenServer's behavior.
///
/// You can use the `new` function to only configure the required values.
/// This module provides functions to configure the optional values.
pub type Spec(args, request, state) {
  Spec(
    /// Initialize the server. This function is called when using `start_link`
    /// or as part of a supervision tree.
    init: fn(args) -> InitResult(state),
    /// The function that handles incoming requests.
    handler: fn(GenServer(request), request, state) -> Next(state),
    /// An optional function that is called when a timeout occurs.
    handle_timeout: Option(fn(state) -> Next(state)),
    /// An optional function that is called when a monitored process exits.
    handle_process_down: Option(fn(ProcessDown, state) -> Next(state)),
    /// An optional name to under which to register the server. A named
    /// `GenServer` reference will still be valid if the process is restarted.
    name: Option(Atom),
  )
}

/// Create a new GenServer specification.
pub fn new(
  init init: fn(args) -> InitResult(state),
  handler handler: fn(GenServer(request), request, state) -> Next(state),
) -> Spec(args, request, state) {
  Spec(
    init:,
    handler:,
    handle_timeout: None,
    handle_process_down: None,
    name: None,
  )
}

/// Add a timeout handler to a Spec.
pub fn handle_timeout(
  spec: Spec(args, request, state),
  handle_timeout: fn(state) -> Next(state),
) -> Spec(args, request, state) {
  Spec(..spec, handle_timeout: Some(handle_timeout))
}

/// Add a handler to a Spec to handle when monitored processes exit.
pub fn handle_process_down(
  spec: Spec(args, request, state),
  handle_process_down: fn(ProcessDown, state) -> Next(state),
) -> Spec(args, request, state) {
  Spec(..spec, handle_process_down: Some(handle_process_down))
}

/// Add a name to a Spec.
/// A named `GenServer` reference will still be valid if the process is
/// restarted.
pub fn name(
  spec: Spec(args, request, state),
  name: Atom,
) -> Spec(args, request, state) {
  Spec(..spec, name: Some(name))
}

/// Start a server, linked to the calling process.
/// If `spec` includes a name, the returned `GenServer` will still be valid if
/// the process is restarted.
pub fn start_link(
  spec: Spec(args, request, state),
  args: args,
) -> Result(GenServer(request), Dynamic) {
  let module = atom.create_from_string("kino@internal@gen_server")
  let builder = to_internal_builder(spec)
  case builder.name {
    None ->
      do_start_link(module, #(builder, args), [])
      |> result.map(PidRef)
    Some(name) ->
      do_start_link_named(Local(name), module, #(builder, args), [])
      |> result.replace(NameRef(name))
  }
}

/// Gets the server's pid. If the server is registered under a name, the pid is
/// only returned if the process still exists.
pub fn owner(server: GenServer(request)) -> Result(Pid, Nil) {
  case server {
    PidRef(pid) -> Ok(pid)
    NameRef(name) -> process.named(name)
  }
}

/// Create a child spec to be added to a static supervisor.
pub fn child_spec(
  spec: Spec(args, request, state),
  id: String,
  args: args,
) -> static_supervisor.ChildBuilder {
  static_supervisor.worker_child(id, fn() {
    start_link(spec, args) |> to_supervise_result
  })
}

/// Create a child spec to be added to a static supervisor.
/// The GenServer will be sent to the `ack` subject when it is started.
pub fn child_spec_ack(
  spec: Spec(args, request, state),
  id: String,
  args: args,
  ack: process.Subject(GenServer(request)),
) -> static_supervisor.ChildBuilder {
  static_supervisor.worker_child(id, fn() {
    start_link(spec, args) |> to_supervise_result_ack(ack)
  })
}

/// Send a synchronous request and wait for a response from the receiving
/// process.
/// If no reply is received within the specified time, this function exits the
/// calling process.
///
pub fn call(
  server: GenServer(request),
  make_request: fn(From(reply)) -> request,
  timeout: Int,
) -> reply {
  let request =
    fn(from) {
      erlang_from(from)
      |> make_request
    }
    |> Call

  case server {
    PidRef(pid) -> do_call(pid, request, timeout)
    NameRef(name) -> do_call(name, request, timeout)
  }
}

/// Similar to `call` but will wait forever for a response.
///
pub fn call_forever(
  server: GenServer(request),
  request: fn(From(reply)) -> request,
) -> reply {
  let timeout = atom.create_from_string("infinity")
  case server {
    PidRef(pid) -> do_call(dynamic.from(pid), request, timeout)
    NameRef(name) -> do_call(dynamic.from(name), request, timeout)
  }
}

/// Send an asynchronous request and returns Nil immediately, ignoring if the
/// server still exists or not.
pub fn cast(server: GenServer(request), request: request) -> Nil {
  let _ = case server {
    PidRef(pid) -> do_cast(pid, request)
    NameRef(name) -> do_cast(name, request)
  }
  Nil
}

/// Send a reply to a client. This function is to be used inside the
/// user-defined handler to handle `calls`.
///
pub fn reply(from: From(message), message: message) -> Nil {
  let _ = do_reply(from, message)
  Nil
}

/// Stop the server
///
pub fn stop(server: GenServer(request)) -> Nil {
  case server {
    PidRef(pid) -> do_stop(pid)
    NameRef(name) -> do_stop(name)
  }
  Nil
}

fn to_supervise_result_ack(
  server: Result(GenServer(request), Dynamic),
  ack: process.Subject(GenServer(request)),
) -> Result(Pid, Dynamic) {
  use server <- result.try(server)
  use pid <- result.map(owner(server) |> result.map_error(dynamic.from))
  process.send(ack, server)
  pid
}

fn to_supervise_result(
  server: Result(GenServer(request), Dynamic),
) -> Result(Pid, Dynamic) {
  result.try(server, fn(server) {
    owner(server) |> result.map_error(dynamic.from)
  })
}

fn to_internal_builder(
  spec: Spec(args, request, state),
) -> gen_server.Builder(args, Call(request), request, State(state, request)) {
  let Spec(init:, handler:, name:, ..) = spec
  gen_server.Builder(
    init: fn(args) {
      case init(args) {
        Ready(state) -> {
          let state = State(state, self(spec.name), handler)
          gen_server.Ready(state, None)
        }
        Timeout(state, timeout) -> {
          let state = State(state, self(spec.name), handler)
          gen_server.Ready(state, Some(timeout))
        }
        Failed(reason) -> gen_server.Failed(reason)
      }
    },
    handle_call: handle_call,
    handle_cast: handle_cast,
    handle_info: handle_info(spec),
    terminate: fn(_, _) { dynamic.from(Nil) },
    name: name,
  )
}

type Call(request) {
  Call(make_request: fn(gen_server.From) -> request)
}

type State(state, request) {
  State(
    state: state,
    self: GenServer(request),
    handler: fn(GenServer(request), request, state) -> Next(state),
  )
}

fn handle_call(
  request: Call(request),
  from: gen_server.From,
  state: State(state, request),
) -> gen_server.Response(State(state, request)) {
  let request = request.make_request(from)
  state.handler(state.self, request, state.state)
  |> next_to_response(state)
}

fn self(name: Option(Atom)) -> GenServer(request) {
  case name {
    None -> PidRef(process.self())
    Some(name) -> NameRef(name)
  }
}

fn handle_cast(
  request: request,
  state: State(state, request),
) -> gen_server.Response(State(state, request)) {
  state.handler(state.self, request, state.state)
  |> next_to_response(state)
}

fn handle_info(spec: Spec(args, request, state)) {
  fn(request: gen_server.Info, state: State(state, request)) {
    case request, spec.handle_process_down, spec.handle_timeout {
      gen_server.ProcessDown(pid, ref, reason), Some(handle), _ ->
        handle(ProcessDown(pid, ref, reason), state.state)

      gen_server.Timeout, _, Some(handle) -> handle(state.state)

      _, _, _ -> default_handle_info(request, state.state)
    }
    |> next_to_response(state)
  }
}

fn default_handle_info(request: gen_server.Info, state: state) -> Next(state) {
  log_warning(
    charlist.from_string("gen_server: ignoring unexpected message: ~s"),
    [charlist.from_string(string.inspect(request))],
  )
  continue(state)
}

fn next_to_response(
  next: Next(state),
  old_state: State(state, request),
) -> gen_server.Response(State(state, request)) {
  case next {
    Continue(state, Some(timeout)) -> {
      let state = State(..old_state, state:)
      gen_server.no_reply(state) |> gen_server.with_timeout(timeout)
    }
    Continue(state, _) -> {
      let state = State(..old_state, state:)
      gen_server.no_reply(state)
    }
    Stop(state, reason) -> {
      let state = State(..old_state, state:)
      gen_server.stop(state, reason)
    }
  }
}

@external(erlang, "kino_ffi", "identity")
fn erlang_from(from: gen_server.From) -> From(reply)

type Name {
  Local(name: Atom)
}

@external(erlang, "gen_server", "start_link")
fn do_start_link(
  module: Atom,
  start_data: #(
    gen_server.Builder(args, call_request, cast_request, state),
    args,
  ),
  options: List(Dynamic),
) -> Result(Pid, Dynamic)

@external(erlang, "gen_server", "start_link")
fn do_start_link_named(
  name: Name,
  module: Atom,
  start_data: #(
    gen_server.Builder(args, call_request, cast_request, state),
    args,
  ),
  options: List(Dynamic),
) -> Result(Pid, Dynamic)

@external(erlang, "gen_server", "stop")
fn do_stop(server: server_ref) -> Dynamic

@external(erlang, "gen_server", "reply")
fn do_reply(from: From(reply), reply: reply) -> Dynamic

@external(erlang, "gen_server", "call")
fn do_call(server: server_ref, request: request, timeout: timeout) -> reply

@external(erlang, "gen_server", "cast")
fn do_cast(server: server_ref, request: request) -> Result(Nil, never)

@external(erlang, "logger", "warning")
fn log_warning(a: Charlist, b: List(Charlist)) -> Nil
