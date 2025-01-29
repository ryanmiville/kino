import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Pid}
import gleam/result
import kino
import kino/child.{type Child, Child}

import kino/internal/supervisor

pub opaque type SupervisorRef {
  SupervisorRef(pid: Pid)
}

pub type Spec =
  kino.Spec(SupervisorRef)

// pub opaque type Spec {
//   Spec(init: fn() -> Result(SupervisorRef, Dynamic))
// }

// pub type Child(ref) {
//   Child(builder: supervisor.ChildBuilder, transform: fn(Pid) -> ref)
// }

pub type Supervisor {
  Supervisor(builder: supervisor.Builder)
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
  spec.init()
}

type SupervisorSpec {
  SupervisorSpec(init: fn() -> supervisor.Builder)
}

fn supervisor_spec_to_spec(in: SupervisorSpec) -> Spec {
  kino.Spec(fn() { supervisor_start_link(in) })
}

fn supervisor_start_link(spec: SupervisorSpec) -> Result(SupervisorRef, Dynamic) {
  supervisor.start_link(spec.init) |> result.map(SupervisorRef)
}

pub fn start_child(
  sup: SupervisorRef,
  child: Child(ref),
) -> Result(ref, Dynamic) {
  let Child(builder, transform) = child
  use pid <- result.map(supervisor.start_child(sup.pid, builder))
  transform(pid)
}

pub fn child(id: String, child: Spec) -> Child(SupervisorRef) {
  let start = fn() { child.init() |> result.map(fn(s) { s.pid }) }
  supervisor.supervisor_child(id, start)
  |> Child(SupervisorRef)
}
