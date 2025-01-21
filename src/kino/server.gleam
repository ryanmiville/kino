import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom
import gleam/erlang/process.{type ExitReason, type Pid}
import gleam/result

pub opaque type Server(message, reply) {
  Server(pid: Pid)
}

pub type From(accepts)

pub type Spec(init_args, message, reply, state) {
  Spec(
    init: fn(init_args) -> Result(state, Dynamic),
    handle_call: fn(message, From(reply), state) -> Response(reply, state),
    handle_cast: fn(message, state) -> Response(reply, state),
    terminate: fn(ExitReason, state) -> Dynamic,
  )
}

pub type Response(reply, state) {
  Reply(reply, state)
  Noreply(state)
  Stop(ExitReason, state)
}

pub fn start_link(
  spec: Spec(init_args, message, reply, state),
  args: init_args,
) -> Result(Server(message, reply), Dynamic) {
  do_start_link(#(spec, args)) |> result.map(Server)
}

pub fn call(
  server: Server(message, reply),
  message: message,
  timeout: Int,
) -> reply {
  do_call(server.pid, message, dynamic.from(timeout))
}

pub fn call_forever(server: Server(message, reply), message: message) -> reply {
  let timeout = atom.create_from_string("infinity") |> dynamic.from
  do_call(server.pid, message, timeout)
}

pub fn cast(server: Server(message, reply), message: message) -> Nil {
  let _ = do_cast(server.pid, message)
  Nil
}

@external(erlang, "gen_server", "call")
fn do_call(pid: Pid, message: message, timeout: Dynamic) -> reply

@external(erlang, "gen_server", "cast")
fn do_cast(pid: Pid, message: message) -> Result(Nil, never)

@internal
pub type State(init_args, message, reply, state) {
  State(state: state, spec: Spec(init_args, message, reply, state))
}

@internal
pub fn init(
  start_data: #(Spec(init_args, message, reply, state), init_args),
) -> Result(State(init_args, message, reply, state), Dynamic) {
  let #(spec, args) = start_data
  use state <- result.map(spec.init(args))
  State(state, spec)
}

@internal
pub fn handle_call(
  request: request,
  from: From(reply),
  state: State(init_args, request, reply, state),
) -> Dynamic {
  state.spec.handle_call(request, from, state.state)
  |> wrap(state)
  |> dynamic.from
}

@internal
pub fn handle_cast(
  request: request,
  state: State(init_args, request, reply, state),
) -> Dynamic {
  state.spec.handle_cast(request, state.state)
  |> wrap(state)
  |> dynamic.from
}

@internal
pub fn handle_info(
  _request: request,
  _state: State(init_args, request, reply, state),
) -> Dynamic {
  panic as "should not be called"
}

@internal
pub fn terminate(
  reason: ExitReason,
  state: State(init_args, request, reply, state),
) -> Dynamic {
  state.spec.terminate(reason, state.state)
}

@internal
pub fn code_change(
  _old_vsn: Dynamic,
  state: State(init_args, request, reply, state),
  _extra: Dynamic,
) -> Result(State(init_args, request, reply, state), Dynamic) {
  Ok(state)
}

fn new_state(old_state, state) {
  State(..old_state, state: state)
}

fn wrap(response, old_state) {
  case response {
    Reply(reply, state) -> {
      Reply(reply, new_state(old_state, state))
    }
    Noreply(state) -> Noreply(new_state(old_state, state))
    Stop(reason, state) -> Stop(reason, new_state(old_state, state))
  }
}

@external(erlang, "kino_ffi", "server_start_link")
fn do_start_link(
  start_data: #(Spec(init_args, message, reply, state), init_args),
) -> Result(Pid, Dynamic)
