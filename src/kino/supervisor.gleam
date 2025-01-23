import gleam/erlang/process.{type Pid}
import kino.{type ActorRef, type Behavior}
import kino/internal/supervisor

pub opaque type Spec {
  Spec(init: fn(Pid) -> supervisor.Builder)
}

pub opaque type Supervisor {
  Supervisor(builder: supervisor.Builder)
}

pub fn spec(supervisor: Supervisor) -> Spec {
  Spec(fn(_) { supervisor.builder })
}

pub opaque type SupervisorRef {
  SupervisorRef(pid: Pid)
}

pub fn init(handler: fn(SupervisorRef) -> Supervisor) -> Spec {
  Spec(fn(pid) { handler(SupervisorRef(pid)).builder })
}

pub fn new(strategy: supervisor.Strategy) -> Supervisor {
  Supervisor(supervisor.new(strategy))
}

pub fn start_link(spec: Spec) -> SupervisorRef {
  let assert Ok(pid) = supervisor.start_link_init(spec.init)
  SupervisorRef(pid)
}

pub opaque type Child(returns) {
  Child(builder: supervisor.ChildBuilder)
}

pub fn add(supervisor: Supervisor, child: Child(a)) -> Supervisor {
  supervisor.builder
  |> supervisor.add(child.builder)
  |> Supervisor
}

pub fn worker_child(
  id: String,
  name: String,
  behavior: Behavior(a),
) -> Child(ActorRef(a)) {
  supervisor.worker_child(id, fn(_) {
    kino.spawn_link(behavior, name)
    |> kino.owner
    |> Ok
  })
  |> Child
}

pub fn supervisor_child(
  id: String,
  supervisor: Supervisor,
) -> Child(SupervisorRef) {
  supervisor.supervisor_child(id, fn(_) {
    supervisor.start_link(supervisor.builder)
  })
  |> Child
}

pub fn start_child(sup: SupervisorRef, child: Child(a)) {
  supervisor.start_child(sup.pid, child.builder)
}

fn example() {
  use self <- init()
  new(supervisor.OneForOne)
  |> add(worker_child("worker", "worker", worker(self)))
}

fn worker(sup: SupervisorRef) -> Behavior(a) {
  kino.continue
}
