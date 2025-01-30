import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Pid, type Subject}
import gleam/result
import kino
import kino/internal/gen_server

pub type Spec(message) =
  kino.Spec(GenServerRef(message))

pub opaque type GenServerRef(message) {
  GenServerRef(ref: gen_server.GenServer(message, Behavior(message)))
}

pub opaque type Behavior(message) {
  Receive(on_receive: fn(GenServerRef(message), message) -> Behavior(message))
  Continue
  Stop
}

pub fn init(
  init: fn(GenServerRef(message)) -> Behavior(message),
) -> Spec(message) {
  GenServerSpec(init) |> gen_server_spec_to_spec
}

pub fn owner(gen_server: GenServerRef(message)) -> Pid {
  gen_server.owner(gen_server.ref)
}

pub fn start_link(spec: Spec(message)) -> Result(GenServerRef(message), Dynamic) {
  kino.start_link(spec)
}

pub const receive = Receive

pub const continue: Behavior(message) = Continue

pub const stopped: Behavior(message) = Stop

pub fn send(gen_server: GenServerRef(message), message: message) -> Nil {
  gen_server.cast(gen_server.ref, message)
}

pub fn call(
  gen_server: GenServerRef(request),
  make_request: fn(Subject(response)) -> request,
  within timeout: Int,
) -> response {
  let assert Ok(resp) = try_call(gen_server, make_request, timeout)
  resp
}

pub fn try_call(
  gen_server: GenServerRef(request),
  make_request: fn(Subject(response)) -> request,
  within timeout: Int,
) -> Result(response, process.CallError(response)) {
  let reply_subject = process.new_subject()

  // Monitor the callee process so we can tell if it goes down (meaning we
  // won't get a reply)
  let owner = gen_server.owner(gen_server.ref)
  let monitor = process.monitor_process(owner)

  // Send the request to the process over the channel
  send(gen_server, make_request(reply_subject))

  // Await a reply or handle failure modes (timeout, process down, etc)
  let result =
    process.new_selector()
    |> process.selecting(reply_subject, Ok)
    |> process.selecting_process_down(monitor, fn(down: process.ProcessDown) {
      Error(process.CalleeDown(reason: down.reason))
    })
    |> process.select(timeout)

  // Demonitor the process and close the channels as we're done
  process.demonitor_process(monitor)

  // Prepare an appropriate error (if present) for the caller
  case result {
    Error(Nil) -> Error(process.CallTimeout)
    Ok(res) -> res
  }
}

pub fn call_forever(
  gen_server: GenServerRef(request),
  make_request: fn(Subject(response)) -> request,
) -> response {
  let assert Ok(resp) = try_call_forever(gen_server, make_request)
  resp
}

pub fn try_call_forever(
  gen_server: GenServerRef(request),
  make_request: fn(Subject(response)) -> request,
) -> Result(response, process.CallError(c)) {
  let reply_subject = process.new_subject()

  // Monitor the callee process so we can tell if it goes down (meaning we
  // won't get a reply)
  let owner = gen_server.owner(gen_server.ref)
  let monitor = process.monitor_process(owner)

  // Send the request to the process over the channel
  send(gen_server, make_request(reply_subject))

  // Await a reply or handle failure modes (timeout, process down, etc)
  let result =
    process.new_selector()
    |> process.selecting(reply_subject, Ok)
    |> process.selecting_process_down(monitor, fn(down) {
      Error(process.CalleeDown(reason: down.reason))
    })
    |> process.select_forever

  // Demonitor the process and close the channels as we're done
  process.demonitor_process(monitor)

  result
}

type GenServerSpec(message) {
  GenServerSpec(init: fn(GenServerRef(message)) -> Behavior(message))
}

fn gen_server_spec_to_spec(in: GenServerSpec(message)) -> Spec(message) {
  kino.Spec(fn() { gen_server_start_link(in) })
}

fn gen_server_start_link(
  spec: GenServerSpec(message),
) -> Result(#(Pid, GenServerRef(message)), Dynamic) {
  let spec = new_gen_server_spec(spec)
  let ref = gen_server.start_link(spec, Nil)
  result.map(ref, fn(ref) { #(gen_server.owner(ref), GenServerRef(ref)) })
}

type ActorState(message) {
  ActorState(self: GenServerRef(message), behavior: Behavior(message))
}

fn new_gen_server_spec(spec: GenServerSpec(message)) {
  gen_server.Spec(
    init: fn(_) {
      let self = GenServerRef(gen_server.self())
      let next = spec.init(self)
      let state = ActorState(self, next)
      Ok(state)
    },
    handle_call:,
    handle_cast:,
    terminate:,
  )
}

fn handle_call(
  _message,
  _from,
  state: state,
) -> gen_server.Response(response, state) {
  gen_server.Noreply(state)
}

fn terminate(_reason, _state) -> Dynamic {
  dynamic.from(Nil)
}

fn handle_cast(message: message, state: ActorState(message)) {
  let ActorState(self, behavior) = state
  case behavior {
    Receive(on_receive) -> {
      case on_receive(self, message) {
        Continue -> gen_server.Noreply(state)
        next -> gen_server.Noreply(ActorState(self, next))
      }
    }
    Continue -> gen_server.Noreply(state)
    Stop -> gen_server.Stop(process.Normal, state)
  }
}
