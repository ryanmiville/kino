import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Pid}
import gleam/result
import kino
import kino/internal/supervisor

pub opaque type SupervisorRef {
  SupervisorRef(pid: Pid)
}

pub type Spec =
  kino.Spec(SupervisorRef)

pub type Supervisor {
  Supervisor(builder: supervisor.Builder)
}

pub opaque type Child(returning) {
  Child(builder: supervisor.ChildBuilder(returning))
}

pub fn owner(supervisor: SupervisorRef) -> Pid {
  supervisor.pid
}

pub fn new() -> Supervisor {
  supervisor.new(supervisor.OneForOne) |> Supervisor
}

pub fn add_child(sup: Supervisor, child: Child(a)) -> Supervisor {
  supervisor.add(sup.builder, child.builder)
  |> Supervisor
}

pub fn init(init: fn(SupervisorRef) -> Supervisor) -> Spec {
  fn() { init(SupervisorRef(process.self())).builder }
  |> SupervisorSpec
  |> supervisor_spec_to_spec
}

pub fn start_link(spec: Spec) -> Result(SupervisorRef, Dynamic) {
  kino.start_link(spec)
}

type SupervisorSpec {
  SupervisorSpec(init: fn() -> supervisor.Builder)
}

fn supervisor_spec_to_spec(in: SupervisorSpec) -> Spec {
  kino.Spec(fn() { supervisor_start_link(in) })
}

fn supervisor_start_link(
  spec: SupervisorSpec,
) -> Result(#(Pid, SupervisorRef), Dynamic) {
  supervisor.start_link(spec.init)
  |> result.map(fn(pid) { #(pid, SupervisorRef(pid)) })
}

pub fn start_child(
  sup: SupervisorRef,
  child: Child(ref),
) -> Result(ref, Dynamic) {
  use #(_, ref) <- result.map(supervisor.start_child(sup.pid, child.builder))
  ref
}

pub fn worker_child(id: String, child: kino.Spec(returning)) -> Child(returning) {
  supervisor.worker_child(id, child.init) |> Child
}

pub fn supervisor_child(
  id: String,
  child: kino.Spec(returning),
) -> Child(returning) {
  supervisor.supervisor_child(id, child.init) |> Child
}
