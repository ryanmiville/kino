import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Pid, type Subject}
import gleam/result
import kino
import kino/child.{type Child, Child}
import kino/internal/gen_server
import kino/internal/supervisor as sup

pub type Spec(message) =
  kino.Spec(ActorRef(message))

// pub opaque type Spec(message) {
//   Spec(init: fn() -> Result(ActorRef(message), Dynamic))
// }

pub opaque type ActorRef(message) {
  ActorRef(ref: gen_server.GenServer(message, Behavior(message)))
}

pub opaque type Behavior(message) {
  Receive(on_receive: fn(ActorRef(message), message) -> Behavior(message))
  Continue
  Stop
}

pub fn init(init: fn(ActorRef(message)) -> Behavior(message)) -> Spec(message) {
  ActorSpec(init) |> actor_spec_to_spec
}

pub fn owner(actor: ActorRef(message)) -> Pid {
  gen_server.owner(actor.ref)
}

pub fn start_link(spec: Spec(message)) -> Result(ActorRef(message), Dynamic) {
  spec.init()
}

pub const receive = Receive

pub const continue: Behavior(message) = Continue

pub const stopped: Behavior(message) = Stop

pub fn send(actor: ActorRef(message), message: message) -> Nil {
  gen_server.cast(actor.ref, message)
}

pub fn call(
  actor: ActorRef(request),
  make_request: fn(Subject(response)) -> request,
  within timeout: Int,
) -> response {
  let assert Ok(resp) = try_call(actor, make_request, timeout)
  resp
}

pub fn try_call(
  actor: ActorRef(request),
  make_request: fn(Subject(response)) -> request,
  within timeout: Int,
) -> Result(response, process.CallError(response)) {
  let reply_subject = process.new_subject()

  // Monitor the callee process so we can tell if it goes down (meaning we
  // won't get a reply)
  let owner = gen_server.owner(actor.ref)
  let monitor = process.monitor_process(owner)

  // Send the request to the process over the channel
  send(actor, make_request(reply_subject))

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
  actor: ActorRef(request),
  make_request: fn(Subject(response)) -> request,
) -> response {
  let assert Ok(resp) = try_call_forever(actor, make_request)
  resp
}

pub fn try_call_forever(
  actor: ActorRef(request),
  make_request: fn(Subject(response)) -> request,
) -> Result(response, process.CallError(c)) {
  let reply_subject = process.new_subject()

  // Monitor the callee process so we can tell if it goes down (meaning we
  // won't get a reply)
  let owner = gen_server.owner(actor.ref)
  let monitor = process.monitor_process(owner)

  // Send the request to the process over the channel
  send(actor, make_request(reply_subject))

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

type ActorSpec(message) {
  ActorSpec(init: fn(ActorRef(message)) -> Behavior(message))
}

fn actor_spec_to_spec(in: ActorSpec(message)) -> Spec(message) {
  kino.Spec(fn() { actor_start_link(in) })
}

fn actor_start_link(
  spec: ActorSpec(message),
) -> Result(ActorRef(message), Dynamic) {
  let spec = new_gen_server_spec(spec)
  let ref = gen_server.start_link(spec, Nil)
  result.map(ref, ActorRef)
}

type ActorState(message) {
  ActorState(self: ActorRef(message), behavior: Behavior(message))
}

fn new_gen_server_spec(spec: ActorSpec(message)) {
  gen_server.Spec(
    init: fn(_) {
      let self = ActorRef(gen_server.self())
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

pub fn child(id: String, child: Spec(message)) -> Child(ActorRef(message)) {
  let start = fn() { child.init() |> result.map(owner) }
  sup.worker_child(id, start)
  |> Child(fn(pid) { ActorRef(gen_server.from_pid(pid)) })
}
