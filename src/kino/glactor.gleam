import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Pid, type Subject}
import gleam/function
import gleam/otp/actor
import gleam/result
import kino
import kino/child.{
  type DynamicChild, type StaticChild, DynamicChild, StaticChild,
}
import kino/internal/gen_server
import kino/internal/supervisor as sup

pub type Spec(message) =
  kino.Spec(ActorRef(message))

// pub opaque type Spec(message) {
//   Spec(init: fn() -> Result(ActorRef(message), Dynamic))
// }

pub opaque type ActorRef(message) {
  ActorRef(subject: Subject(message))
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
  process.subject_owner(actor.subject)
}

pub fn start_link(spec: Spec(message)) -> Result(ActorRef(message), Dynamic) {
  spec.init()
}

pub const receive = Receive

pub const continue: Behavior(message) = Continue

pub const stopped: Behavior(message) = Stop

pub fn send(actor: ActorRef(message), message: message) -> Nil {
  process.send(actor.subject, message)
}

pub fn call(
  actor: ActorRef(request),
  make_request: fn(Subject(response)) -> request,
  within timeout: Int,
) -> response {
  process.call(actor.subject, make_request, timeout)
}

pub fn try_call(
  actor: ActorRef(request),
  make_request: fn(Subject(response)) -> request,
  within timeout: Int,
) -> Result(response, process.CallError(response)) {
  process.try_call(actor.subject, make_request, timeout)
}

pub fn call_forever(
  actor: ActorRef(request),
  make_request: fn(Subject(response)) -> request,
) -> response {
  process.call_forever(actor.subject, make_request)
}

pub fn try_call_forever(
  actor: ActorRef(request),
  make_request: fn(Subject(response)) -> request,
) -> Result(response, process.CallError(c)) {
  process.try_call_forever(actor.subject, make_request)
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
  let spec = new_spec(spec.init)
  let ref = actor.start_spec(spec)
  result.map(ref, ActorRef)
  |> result.map_error(dynamic.from)
}

type ActorState(message) {
  ActorState(self: ActorRef(message), behavior: Behavior(message))
}

fn new_spec(init: fn(ActorRef(message)) -> Behavior(message)) {
  actor.Spec(
    init: fn() {
      let self = ActorRef(process.new_subject())
      let next = init(self)
      let state = ActorState(self, next)
      let selector =
        process.new_selector()
        |> process.selecting(self.subject, function.identity)
      actor.Ready(state, selector)
    },
    init_timeout: 5000,
    loop: loop,
  )
}

fn loop(
  message: message,
  state: ActorState(message),
) -> actor.Next(message, ActorState(message)) {
  let ActorState(context, behavior) = state
  case behavior {
    Stop -> {
      actor.Stop(process.Normal)
    }

    Continue -> {
      actor.continue(state)
    }

    Receive(handler) -> {
      let next_behavior = handler(context, message)
      case next_behavior {
        Continue -> actor.continue(state)
        _ -> actor.continue(ActorState(context, next_behavior))
      }
    }
  }
}
// pub fn static_child(
//   id: String,
//   child: Spec(message),
// ) -> StaticChild(ActorRef(message)) {
//   let start = fn() { child.init() |> result.map(owner) }
//   sup.worker_child(id, start)
//   |> StaticChild(fn(pid) { ActorRef(pid) })
// }

// pub fn dynamic_child(spec: Spec(message)) -> DynamicChild(ActorRef(message)) {
//   DynamicChild(spec, fn(pid) { ActorRef(pid) })
// }
