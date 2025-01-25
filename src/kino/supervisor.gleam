import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Pid}
import gleam/result
import kino.{type ActorRef}
import kino/internal/gen_server
import kino/internal/supervisor as sup

pub opaque type Spec {
  Spec(init: fn() -> sup.Builder)
}

pub opaque type Supervisor {
  Supervisor(builder: sup.Builder)
}

pub fn spec(supervisor: Supervisor) -> Spec {
  Spec(fn() { supervisor.builder })
}

pub opaque type SupervisorRef {
  SupervisorRef(pid: Pid)
}

pub fn init(on_init: fn(SupervisorRef) -> Supervisor) -> Spec {
  Spec(init: fn() { on_init(SupervisorRef(process.self())).builder })
}

pub fn new(strategy: sup.Strategy) -> Supervisor {
  Supervisor(sup.new(strategy))
}

pub fn start_link(spec: Spec) -> SupervisorRef {
  let assert Ok(pid) = sup.start_link(spec.init)
  SupervisorRef(pid)
}

pub opaque type Child(returns) {
  Child(builder: sup.ChildBuilder)
}

pub fn add(supervisor: Supervisor, child: Child(a)) -> Supervisor {
  supervisor.builder
  |> sup.add(child.builder)
  |> Supervisor
}

pub fn worker_child(id: String, child: kino.Spec(a)) -> Child(ActorRef(a)) {
  sup.worker_child(id, fn() {
    kino.start_link(child)
    |> result.map(kino.owner)
  })
  |> Child
}

pub fn supervisor_child(
  id: String,
  supervisor: Supervisor,
) -> Child(SupervisorRef) {
  sup.supervisor_child(id, fn() { sup.start_link(fn() { supervisor.builder }) })
  |> Child
}

pub fn start_worker_child(
  supervisor: SupervisorRef,
  child: Child(ActorRef(message)),
) -> Result(ActorRef(message), Dynamic) {
  use pid <- result.map(sup.start_child(supervisor.pid, child.builder))
  gen_server.from_pid(pid) |> kino.from_gen_server
}

pub fn start_supervisor_child(
  supervisor: SupervisorRef,
  child: Child(SupervisorRef),
) -> Result(SupervisorRef, Dynamic) {
  use pid <- result.map(sup.start_child(supervisor.pid, child.builder))
  SupervisorRef(pid)
}
