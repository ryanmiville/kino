import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Pid, type Selector, type Subject}
import gleam/function
import gleam/otp/actor
import gleam/result
import kino

pub type Spec(message) =
  kino.Spec(ActorRef(message))

pub opaque type ActorRef(message) {
  ActorRef(subject: Subject(message))
}

pub opaque type NextSelector(message) {
  SameSelector
  ReplaceSelector(selector: Selector(message))
  AddSelector(selector: Selector(message))
}

pub opaque type Behavior(message) {
  Receive(
    on_receive: fn(ActorRef(message), message) -> Behavior(message),
    selector: NextSelector(message),
  )
  Continue(selector: NextSelector(message))
  Stop
}

pub fn add_selector(
  behavior: Behavior(message),
  selector: Selector(message),
) -> Behavior(message) {
  case behavior {
    Receive(on_receive, _) -> Receive(on_receive, AddSelector(selector))
    Continue(_) -> Continue(AddSelector(selector))
    Stop -> Stop
  }
}

pub fn replace_selector(
  behavior: Behavior(message),
  selector: Selector(message),
) -> Behavior(message) {
  case behavior {
    Receive(on_receive, _) -> Receive(on_receive, ReplaceSelector(selector))
    Continue(_) -> Continue(ReplaceSelector(selector))
    Stop -> Stop
  }
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

pub fn receive(on_receive: fn(ActorRef(message), message) -> Behavior(message)) {
  Receive(on_receive, SameSelector)
}

pub fn continue() -> Behavior(message) {
  Continue(SameSelector)
}

pub const stopped: Behavior(message) = Stop

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

    Continue(SameSelector) -> actor.continue(state)
    Continue(AddSelector(new_selector)) -> {
      actor.continue(state)
      |> actor.with_selector(process.merge_selector(selector, new_selector))
    }
    Continue(ReplaceSelector(new_selector)) ->
      actor.continue(state) |> actor.with_selector(new_selector)

    Receive(handler, selector) -> {
      let selector = case selector {
        SameSelector -> state.selector
        AddSelector(new_selector) ->
          process.merge_selector(state.selector, new_selector)
        ReplaceSelector(new_selector) -> new_selector
      }
      let state = ActorState(self, selector, behavior)
      let next_behavior = handler(self, message)

      case next_behavior {
        Stop -> actor.Stop(process.Normal)

        Continue(SameSelector) -> actor.continue(state)
        Continue(AddSelector(new_selector)) -> {
          actor.continue(state)
          |> actor.with_selector(process.merge_selector(selector, new_selector))
        }
        Continue(ReplaceSelector(new_selector)) ->
          actor.continue(state) |> actor.with_selector(new_selector)

        _ ->
          actor.continue(ActorState(self, selector, next_behavior))
          |> actor.with_selector(selector)
      }
    }
  }
}
// fn monitor(pid, selector, mapping) {
//   process.selecting_process_down(
//     selector,
//     process.monitor_process(pid),
//     mapping,
//   )
// }
