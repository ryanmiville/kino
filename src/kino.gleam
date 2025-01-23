import gleam/erlang/process.{type Subject}
import gleam/function
import gleam/otp/actor
import kino/internal/dynamic_supervisor
import kino/internal/supervisor

pub opaque type Context(message) {
  Context(self: ActorRef(message))
}

fn start() -> Context(message) {
  process.new_subject()
  |> ActorRef
  |> Context
}

pub opaque type Behavior(message) {
  Receive(handler: fn(Context(message), message) -> Behavior(message))
  Init(handler: fn(Context(message)) -> Behavior(message))
  Continue
  Stop
}

pub const receive = Receive

pub const init = Init

pub const continue: Behavior(message) = Continue

pub const stopped: Behavior(message) = Stop

pub opaque type ActorRef(message) {
  ActorRef(subject: Subject(message))
}

pub fn spawn_link(behavior: Behavior(b), _name: String) -> ActorRef(b) {
  let subject =
    new_spec(behavior)
    |> actor.start_spec

  case subject {
    Ok(subject) -> ActorRef(subject)
    Error(_) -> panic as "failed to start actor"
  }
}

pub fn self(context: Context(message)) -> ActorRef(message) {
  context.self
}

pub fn owner(actor: ActorRef(message)) -> process.Pid {
  process.subject_owner(actor.subject)
}

pub fn send(actor: ActorRef(message), message: message) -> Nil {
  process.send(actor.subject, message)
}

fn new_spec(behavior: Behavior(message)) -> Spec(message) {
  actor.Spec(
    init: fn() {
      case behavior {
        Init(handler) -> {
          let context = start()
          let next = handler(context)
          let state = State(context, next)
          let selector =
            process.new_selector()
            |> process.selecting(context.self.subject, function.identity)
          actor.Ready(state, selector)
        }

        _ -> {
          let context = start()
          let state = State(context, behavior)
          let selector =
            process.new_selector()
            |> process.selecting(context.self.subject, function.identity)
          actor.Ready(state, selector)
        }
      }
    },
    init_timeout: 5000,
    loop: loop,
  )
}

type State(message) {
  State(Context(message), Behavior(message))
}

type Spec(message) =
  actor.Spec(State(message), message)

fn loop(
  message: message,
  state: State(message),
) -> actor.Next(message, State(message)) {
  let State(context, behavior) = state
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
        _ -> actor.continue(State(context, next_behavior))
      }
    }

    Init(handler) -> {
      let next_behavior = handler(context)
      actor.continue(State(context, next_behavior))
    }
  }
}

// Supervision :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

// pub opaque type Supervisor(message) {
//   Supervisor(Behavior(message))
// }

// pub fn supervise(behavior: Behavior(message)) -> Supervisor(message) {
//   Supervisor(behavior)
// }

pub opaque type Supervisor {
  Supervisor(builder: supervisor.Builder)
}

pub opaque type SupervisorRef {
  SupervisorRef(pid: process.Pid)
}

pub opaque type DynamicSupervisor(init_arg) {
  DynamicSupervisor(builder: dynamic_supervisor.Builder(init_arg))
}

pub opaque type DynamicSupervisorRef(init_arg) {
  DynamicSupervisorRef(pid: process.Pid)
}

pub fn new_supervisor() -> Supervisor {
  supervisor.new(supervisor.OneForOne) |> Supervisor
}

pub fn add_worker(
  supervisor: Supervisor,
  starter: fn() -> Behavior(a),
) -> Supervisor {
  supervisor.builder |> supervisor.add(child_spec(starter)) |> Supervisor
}

pub fn add_supervisor(supervisor: Supervisor, child: Supervisor) -> Supervisor {
  supervisor.builder
  |> supervisor.add(supervisor_child_spec(child))
  |> Supervisor
}

pub fn add_dynamic_supervisor(
  supervisor: Supervisor,
  child: DynamicSupervisor(a),
) -> Supervisor {
  supervisor.builder
  |> supervisor.add(dynamic_supervisor_child_spec(child))
  |> Supervisor
}

pub fn new_dynamic_supervisor(
  starter: fn(init_arg) -> Behavior(a),
) -> DynamicSupervisor(init_arg) {
  todo
}

pub fn child_spec(starter: fn() -> Behavior(a)) {
  todo
}

pub fn supervisor_child_spec(supervisor: Supervisor) {
  todo
}

pub fn dynamic_supervisor_child_spec(supervisor: DynamicSupervisor(a)) {
  todo
}
