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

pub opaque type Server(request) {
  PidRef(Pid)
  NameRef(Atom)
}

pub type InitResult(state) {
  Ready(state: state)
  Timeout(state: state, timeout: Int)
  Failed(reason: Dynamic)
}

pub type From(accepts)

pub type Next(state) {
  Continue(state: state, timeout: Option(Int))
  Stop(state: state, reason: ExitReason)
}

pub type ProcessDown {
  ProcessDown(pid: Pid, ref: Reference, reason: Dynamic)
}

pub fn continue(state: state) -> Next(state) {
  Continue(state, None)
}

pub fn with_timeout(next: Next(state), timeout: Int) -> Next(state) {
  case next {
    Continue(state, _) -> Continue(state, Some(timeout))
    _ -> next
  }
}

pub type Builder(args, request, state) {
  Builder(
    init: fn(args) -> InitResult(state),
    handler: fn(Server(request), request, state) -> Next(state),
    handle_timeout: Option(fn(state) -> Next(state)),
    handle_process_down: Option(fn(ProcessDown, state) -> Next(state)),
    name: Option(Atom),
  )
}

pub fn new(
  init init: fn(args) -> InitResult(state),
  handler handler: fn(Server(request), request, state) -> Next(state),
) -> Builder(args, request, state) {
  Builder(
    init:,
    handler:,
    handle_timeout: None,
    handle_process_down: None,
    name: None,
  )
}

pub fn handle_timeout(
  builder: Builder(args, request, state),
  handle_timeout: fn(state) -> Next(state),
) -> Builder(args, request, state) {
  Builder(..builder, handle_timeout: Some(handle_timeout))
}

pub fn handle_process_down(
  builder: Builder(args, request, state),
  handle_process_down: fn(ProcessDown, state) -> Next(state),
) -> Builder(args, request, state) {
  Builder(..builder, handle_process_down: Some(handle_process_down))
}

pub fn name(
  builder: Builder(args, request, state),
  name: Atom,
) -> Builder(args, request, state) {
  Builder(..builder, name: Some(name))
}

pub fn start_link(
  builder: Builder(args, request, state),
  args: args,
) -> Result(Server(request), Dynamic) {
  let module = atom.create_from_string("kino@internal@gen_server")
  let builder = to_internal_builder(builder)
  case builder.name {
    None ->
      do_start_link(module, #(builder, args), [])
      |> result.map(PidRef)
    Some(name) ->
      do_start_link_named(Local(name), module, #(builder, args), [])
      |> result.replace(NameRef(name))
  }
}

pub fn to_supervise_result_ack(
  server: Result(Server(request), Dynamic),
  ack: process.Subject(Server(request)),
) -> Result(Pid, Dynamic) {
  use server <- result.try(server)
  use pid <- result.map(owner(server) |> result.map_error(dynamic.from))
  process.send(ack, server)
  pid
}

pub fn to_supervise_result(
  server: Result(Server(request), Dynamic),
) -> Result(Pid, Dynamic) {
  result.try(server, fn(server) {
    owner(server) |> result.map_error(dynamic.from)
  })
}

pub fn owner(server: Server(request)) -> Result(Pid, Nil) {
  case server {
    PidRef(pid) -> Ok(pid)
    NameRef(name) -> process.named(name)
  }
}

pub fn child_spec(
  builder: Builder(args, request, state),
  id: String,
  args: args,
) -> static_supervisor.ChildBuilder {
  static_supervisor.worker_child(id, fn() {
    start_link(builder, args) |> to_supervise_result
  })
}

pub fn child_spec_ack(
  builder: Builder(args, request, state),
  id: String,
  args: args,
  ack: process.Subject(Server(request)),
) -> static_supervisor.ChildBuilder {
  static_supervisor.worker_child(id, fn() {
    start_link(builder, args) |> to_supervise_result_ack(ack)
  })
}

pub fn call(
  server: Server(request),
  request: fn(From(reply)) -> request,
  timeout: Int,
) -> reply {
  let request =
    fn(from) {
      erlang_from(from)
      |> request
    }
    |> Call

  case server {
    PidRef(pid) -> do_call(pid, request, timeout)
    NameRef(name) -> do_call(name, request, timeout)
  }
}

pub fn call_forever(
  server: Server(request),
  request: fn(From(reply)) -> request,
) -> reply {
  let timeout = atom.create_from_string("infinity")
  case server {
    PidRef(pid) -> do_call(dynamic.from(pid), request, timeout)
    NameRef(name) -> do_call(dynamic.from(name), request, timeout)
  }
}

pub fn cast(server: Server(request), request: request) -> Nil {
  let _ = case server {
    PidRef(pid) -> do_cast(pid, request)
    NameRef(name) -> do_cast(name, request)
  }
  Nil
}

pub fn reply(from: From(message), message: message) -> Nil {
  let _ = do_reply(from, message)
  Nil
}

pub fn stop(server: Server(request)) -> Nil {
  case server {
    PidRef(pid) -> do_stop(pid)
    NameRef(name) -> do_stop(name)
  }
  Nil
}

fn to_internal_builder(
  builder: Builder(args, request, state),
) -> gen_server.Builder(args, Call(request), request, State(state, request)) {
  let Builder(init:, handler:, name:, ..) = builder
  gen_server.Builder(
    init: fn(args) {
      case init(args) {
        Ready(state) -> {
          let state = State(state, self(builder.name), handler)
          gen_server.Ready(state, None)
        }
        Timeout(state, timeout) -> {
          let state = State(state, self(builder.name), handler)
          gen_server.Ready(state, Some(timeout))
        }
        Failed(reason) -> gen_server.Failed(reason)
      }
    },
    handle_call: handle_call,
    handle_cast: handle_cast,
    handle_info: handle_info(builder),
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
    self: Server(request),
    handler: fn(Server(request), request, state) -> Next(state),
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

fn self(name: Option(Atom)) -> Server(request) {
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

fn handle_info(builder: Builder(args, request, state)) {
  fn(request: gen_server.Info, state: State(state, request)) {
    case request, builder.handle_process_down, builder.handle_timeout {
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
