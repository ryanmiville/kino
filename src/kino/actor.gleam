import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{
  type Pid, type ProcessDown, type Selector, type Subject,
}
import gleam/function
import gleam/otp/actor
import gleam/result
import kino

pub type Spec(message) =
  kino.Spec(ActorRef(message))

pub opaque type ActorRef(message) {
  ActorRef(subject: Subject(message))
}

pub opaque type Behavior(message) {
  Receive(on_receive: fn(ActorRef(message), message) -> Behavior(message))
  Continue
  Monitoring(
    next: Behavior(message),
    process: Pid,
    mapping: fn(ProcessDown) -> message,
  )
  Stop
}

pub fn init(init: fn(ActorRef(message)) -> Behavior(message)) -> Spec(message) {
  ActorSpec(init) |> actor_spec_to_spec
}

pub fn owner(actor: ActorRef(message)) -> Pid {
  process.subject_owner(actor.subject)
}

pub fn start_link(spec: Spec(message)) -> Result(ActorRef(message), Dynamic) {
  kino.start_link(spec)
}

pub const receive = Receive

pub const continue: Behavior(message) = Continue

pub const stopped: Behavior(message) = Stop

pub const monitoring = Monitoring

pub fn send(actor: ActorRef(message), message: message) -> Nil {
  process.send(actor.subject, message)
}

pub fn send_after(
  actor: ActorRef(message),
  delay: Int,
  message: message,
) -> process.Timer {
  process.send_after(actor.subject, delay, message)
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
) -> Result(#(Pid, ActorRef(message)), Dynamic) {
  let spec = new_spec(spec.init)
  let ref = actor.start_spec(spec)
  result.map(ref, fn(subject) {
    #(process.subject_owner(subject), ActorRef(subject))
  })
  |> result.map_error(dynamic.from)
}

type ActorState(message) {
  ActorState(
    self: ActorRef(message),
    selector: Selector(message),
    behavior: Behavior(message),
  )
}

fn new_spec(init: fn(ActorRef(message)) -> Behavior(message)) {
  actor.Spec(
    init: fn() {
      let self = ActorRef(process.new_subject())
      let next = init(self)
      let selector =
        process.new_selector()
        |> process.selecting(self.subject, function.identity)
      let state = ActorState(self, selector, next)
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
  let ActorState(self, selector, behavior) = state
  case behavior {
    Stop -> actor.Stop(process.Normal)

    Continue -> actor.continue(state) |> actor.with_selector(selector)

    Monitoring(next, process, mapping) -> {
      let selector = monitor(process, selector, mapping)
      let state = ActorState(self:, selector:, behavior: next)
      actor.continue(state) |> actor.with_selector(selector)
    }

    Receive(handler) -> {
      let next_behavior = handler(self, message)

      case next_behavior {
        Stop -> actor.Stop(process.Normal)

        Continue -> actor.continue(state) |> actor.with_selector(selector)

        Monitoring(Continue, process, mapping) -> {
          let selector = monitor(process, selector, mapping)
          let state = ActorState(..state, selector:)
          actor.continue(state) |> actor.with_selector(selector)
        }

        Monitoring(next, process, mapping) -> {
          let selector = monitor(process, selector, mapping)
          let state = ActorState(self:, selector:, behavior: next)
          actor.continue(state) |> actor.with_selector(selector)
        }

        _ ->
          actor.continue(ActorState(self, selector, next_behavior))
          |> actor.with_selector(selector)
      }
    }
  }
}

fn monitor(pid, selector, mapping) {
  process.selecting_process_down(
    selector,
    process.monitor_process(pid),
    mapping,
  )
}
