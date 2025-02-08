import gleam/dynamic.{type Dynamic}
import gleam/erlang.{type Reference}
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type ExitReason, type Pid}
import gleam/option.{type Option, None, Some}

pub type From

pub opaque type Response(state) {
  Noreply(state: state, timeout: Dynamic)
  Stop(ExitReason, state)
}

pub fn no_reply(state: state) -> Response(state) {
  Noreply(state, dynamic.from(Infinity))
}

pub fn with_timeout(response: Response(state), timeout: Int) -> Response(state) {
  case response {
    Noreply(state, _) -> Noreply(state, dynamic.from(timeout))
    _ -> response
  }
}

pub fn stop(state: state, reason: ExitReason) -> Response(state) {
  Stop(reason, state)
}

pub type Info {
  Timeout
  ProcessDown(pid: Pid, ref: Reference, reason: Dynamic)
  Unexpected(Dynamic)
}

pub type InitResult(state) {
  Ready(state: state, timeout: Option(Int))
  Failed(reason: Dynamic)
}

pub type Builder(args, call_request, cast_request, state) {
  Builder(
    init: fn(args) -> InitResult(state),
    handle_call: fn(call_request, From, state) -> Response(state),
    handle_cast: fn(cast_request, state) -> Response(state),
    handle_info: fn(Info, state) -> Response(state),
    terminate: fn(ExitReason, state) -> Dynamic,
    name: Option(Atom),
  )
}

pub type State(args, call_request, cast_request, state) {
  State(state: state, builder: Builder(args, call_request, cast_request, state))
}

type Infinity {
  Infinity
}

pub fn timeout(timeout: Option(Int)) -> Dynamic {
  case timeout {
    None -> dynamic.from(Infinity)
    Some(timeout) -> dynamic.from(timeout)
  }
}

pub fn init(
  start_data: #(Builder(args, call_request, cast_request, state), args),
) -> Dynamic {
  let #(builder, args) = start_data
  case builder.init(args) {
    Ready(state, Some(timeout)) ->
      #(atom.create_from_string("ok"), State(state, builder), timeout)
      |> dynamic.from
    Ready(state, _) -> Ok(State(state, builder)) |> dynamic.from
    Failed(reason) -> Error(reason) |> dynamic.from
  }
}

pub fn handle_call(
  request: call_request,
  from: From,
  state: State(args, call_request, cast_request, state),
) -> Dynamic {
  state.builder.handle_call(request, from, state.state)
  |> wrap(state)
  |> dynamic.from
}

pub fn handle_cast(
  request: cast_request,
  state: State(args, call_request, cast_request, state),
) -> Dynamic {
  state.builder.handle_cast(request, state.state)
  |> wrap(state)
  |> dynamic.from
}

pub fn handle_info(
  request: Dynamic,
  state: State(args, call_request, cast_request, state),
) -> Dynamic {
  state.builder.handle_info(convert_handle_info_request(request), state.state)
  |> wrap(state)
  |> dynamic.from
}

pub fn terminate(
  reason: ExitReason,
  state: State(args, call_request, cast_request, state),
) -> Dynamic {
  state.builder.terminate(reason, state.state)
}

pub fn code_change(
  _old_vsn: Dynamic,
  state: State(args, call_request, cast_request, state),
  _extra: Dynamic,
) -> Result(State(args, call_request, cast_request, state), Dynamic) {
  Ok(state)
}

@external(erlang, "kino_ffi", "gen_server_format_status")
pub fn format_status(status: status) -> status

fn new_state(old_state, state) {
  State(..old_state, state: state)
}

fn wrap(response, old_state) {
  case response {
    Noreply(state, timeout) -> Noreply(new_state(old_state, state), timeout)
    Stop(reason, state) -> Stop(reason, new_state(old_state, state))
  }
}

@external(erlang, "kino_ffi", "convert_handle_info_request")
fn convert_handle_info_request(request: Dynamic) -> Info
