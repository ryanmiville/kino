import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Pid, type Subject}
import gleam/list
import gleam/result
import kino/internal/dynamic_supervisor as dyn
import kino/internal/gen_server
import kino/internal/supervisor as sup

pub type Spec(ref) {
  Spec(init: fn() -> Result(ref, Dynamic))
}

pub opaque type ActorRef(message) {
  ActorRef(ref: gen_server.GenServer(message, Behavior(message)))
}

pub opaque type SupervisorRef {
  SupervisorRef(pid: Pid)
}

pub opaque type DynamicSupervisorRef(init_arg, child_ref) {
  DynamicSupervisorRef(sup: dyn.DynamicSupervisor(init_arg))
}

pub opaque type Context(ref) {
  Context(self: ref)
}

pub opaque type Behavior(message) {
  Receive(
    on_receive: fn(Context(ActorRef(message)), message) -> Behavior(message),
  )
  Continue
  Stop
}

pub fn actor(
  init: fn(Context(ActorRef(message))) -> Behavior(message),
) -> Spec(ActorRef(message)) {
  ActorSpec(init) |> actor_spec_to_spec
}

pub opaque type Child {
  Child(builder: sup.ChildBuilder)
}

pub fn supervisor(
  init: fn(Context(SupervisorRef)) -> List(Child),
) -> Spec(SupervisorRef) {
  fn() {
    let s = sup.new(sup.OneForOne)
    let context = Context(SupervisorRef(process.self()))
    let children = init(context)
    list.fold(children, s, fn(s, child) { sup.add(s, child.builder) })
  }
  |> SupervisorSpec
  |> supervisor_spec_to_spec
}

pub opaque type DynamicChild(init_arg, child_ref) {
  WorkerChild(init: fn(init_arg) -> Result(Pid, Dynamic))
  SupervisorChild(init: fn(init_arg) -> Result(Pid, Dynamic))
}

pub fn dynamic_supervisor(
  init: fn(Context(DynamicSupervisorRef(init_arg, child_ref))) ->
    DynamicChild(init_arg, child_ref),
) -> Spec(DynamicSupervisorRef(init_arg, child_ref)) {
  fn() {
    let context = Context(DynamicSupervisorRef(dyn.self()))
    case init(context) {
      WorkerChild(init:) -> dyn.worker_child("", init)
      SupervisorChild(init:) -> dyn.supervisor_child("", init)
    }
    |> dyn.new
  }
  |> DynamicSupervisorSpec
  |> dynamic_supervisor_spec_to_spec
}

pub fn self(context: Context(ref)) -> ref {
  context.self
}

pub fn start_link(spec: Spec(ref)) -> Result(ref, Dynamic) {
  spec.init()
}

// :::: Actor :::::::::::::::::::::::::

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
  ActorSpec(init: fn(Context(ActorRef(message))) -> Behavior(message))
}

fn actor_spec_to_spec(in: ActorSpec(message)) -> Spec(ActorRef(message)) {
  Spec(fn() { actor_start_link(in) })
}

fn actor_start_link(
  spec: ActorSpec(message),
) -> Result(ActorRef(message), Dynamic) {
  let spec = new_gen_server_spec(spec)
  let ref = gen_server.start_link(spec, Nil)
  result.map(ref, ActorRef)
}

type ActorState(message) {
  ActorState(context: Context(ActorRef(message)), behavior: Behavior(message))
}

fn new_gen_server_spec(spec: ActorSpec(message)) {
  gen_server.Spec(
    init: fn(_) {
      let context = new_context()
      let next = spec.init(context)
      let state = ActorState(context, next)
      Ok(state)
    },
    handle_call:,
    handle_cast:,
    terminate:,
  )
}

fn new_context() -> Context(ActorRef(message)) {
  Context(ActorRef(gen_server.self()))
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
  let ActorState(context, behavior) = state
  case behavior {
    Receive(on_receive) -> {
      case on_receive(context, message) {
        Continue -> gen_server.Noreply(state)
        next -> gen_server.Noreply(ActorState(context, next))
      }
    }
    Continue -> gen_server.Noreply(state)
    Stop -> gen_server.Stop(process.Normal, state)
  }
}

pub fn supervise(
  actor: Spec(ActorRef(message)),
  id: String,
) -> Spec(ActorRef(message)) {
  let self = process.new_subject()
  let child =
    sup.worker_child(id, fn() {
      use ref <- result.map(actor.init())
      process.send(self, ref)
      gen_server.owner(ref.ref)
    })

  let builder = sup.new(sup.OneForOne) |> sup.add(child)
  Spec(fn() {
    let assert Ok(_) = sup.start_link(fn() { builder })
    let assert Ok(ref) = process.receive(self, 5000)
    Ok(ref)
  })
}

// :::: Supervisor ::::::::::::::::::::

type SupervisorSpec {
  SupervisorSpec(init: fn() -> sup.Builder)
}

fn supervisor_spec_to_spec(in: SupervisorSpec) -> Spec(SupervisorRef) {
  Spec(fn() { supervisor_start_link(in) })
}

fn supervisor_start_link(spec: SupervisorSpec) -> Result(SupervisorRef, Dynamic) {
  sup.start_link(spec.init) |> result.map(SupervisorRef)
}

pub fn worker_child(id: String, child: Spec(ActorRef(message))) -> Child {
  sup.worker_child(id, fn() {
    use ref <- result.map(child.init())
    gen_server.owner(ref.ref)
  })
  |> Child
}

pub fn supervisor_child(id: String, child: Spec(SupervisorRef)) -> Child {
  sup.supervisor_child(id, fn() {
    use ref <- result.map(child.init())
    ref.pid
  })
  |> Child
}

pub fn start_worker_child(
  sup: SupervisorRef,
  id: String,
  child: Spec(ActorRef(message)),
) -> Result(ActorRef(message), Dynamic) {
  use pid <- result.map(sup.start_child(
    sup.pid,
    worker_child(id, child).builder,
  ))
  ActorRef(gen_server.from_pid(pid))
}

pub fn start_supervisor_child(
  sup: SupervisorRef,
  id: String,
  child: Spec(SupervisorRef),
) -> Result(SupervisorRef, Dynamic) {
  use pid <- result.map(sup.start_child(
    sup.pid,
    supervisor_child(id, child).builder,
  ))
  SupervisorRef(pid)
}

// :::: Dynamic Supervisor ::::::::::::

type DynamicSupervisorSpec(init_arg, child_ref) {
  DynamicSupervisorSpec(init: fn() -> dyn.Builder(init_arg))
}

fn dynamic_supervisor_spec_to_spec(
  in: DynamicSupervisorSpec(init_arg, child_ref),
) -> Spec(DynamicSupervisorRef(init_arg, child_ref)) {
  Spec(fn() { dynamic_supervisor_start_link(in) })
}

fn dynamic_supervisor_start_link(
  spec: DynamicSupervisorSpec(init_arg, child_ref),
) -> Result(DynamicSupervisorRef(init_arg, child_ref), Dynamic) {
  dyn.start_link(spec.init())
  |> result.map(DynamicSupervisorRef)
}

pub fn dynamic_worker_child(
  child: fn(init_arg) -> Spec(ActorRef(message)),
) -> DynamicChild(init_arg, ActorRef(message)) {
  WorkerChild(fn(arg) {
    use ref <- result.map(child(arg).init())
    gen_server.owner(ref.ref)
  })
}

pub fn dynamic_supervisor_child(
  child: fn(init_arg) -> Spec(SupervisorRef),
) -> DynamicChild(init_arg, SupervisorRef) {
  SupervisorChild(fn(arg) {
    use ref <- result.map(child(arg).init())
    ref.pid
  })
}

pub fn start_dynamic_worker_child(
  sup: DynamicSupervisorRef(init_arg, ActorRef(message)),
  arg: init_arg,
) -> Result(ActorRef(message), Dynamic) {
  use pid <- result.map(dyn.start_child(sup.sup, arg))
  ActorRef(gen_server.from_pid(pid))
}

pub fn start_dynamic_supervisor_child(
  sup: DynamicSupervisorRef(init_arg, SupervisorRef),
  arg: init_arg,
) -> Result(SupervisorRef, Dynamic) {
  use pid <- result.map(dyn.start_child(sup.sup, arg))
  SupervisorRef(pid)
}
