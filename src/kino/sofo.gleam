import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Pid}
import gleam/result
import kino
import kino/child.{
  type DynamicChild, type StaticChild, DynamicChild, StaticChild,
}
import kino/internal/dynamic_supervisor as dyn
import kino/internal/supervisor

pub type Spec(returning) =
  kino.Spec(DynamicSupervisorRef(returning))

pub opaque type DynamicSupervisorRef(returning) {
  DynamicSupervisorRef(pid: Pid)
}

pub type DynamicSupervisor(returning) {
  DynamicSupervisor(builder: dyn.Builder(kino.Spec(returning)))
}

pub fn init(
  init: fn(DynamicSupervisorRef(returning)) -> DynamicSupervisor(returning),
) -> Spec(returning) {
  fn() {
    init(DynamicSupervisorRef(process.self())).builder
    |> dyn.start_link
    |> result.map(dyn.owner)
    |> result.map(DynamicSupervisorRef)
  }
  |> kino.Spec
}

pub fn start_link(
  spec: Spec(returning),
) -> Result(DynamicSupervisorRef(returning), Dynamic) {
  kino.start_link(spec)
}

pub fn start_child(
  ref: DynamicSupervisorRef(returning),
  child: DynamicChild(returning),
) -> Result(returning, Dynamic) {
  dyn.start_child(dyn.from_pid(ref.pid), child.spec)
  |> result.map(child.transform)
}

pub fn static_child(
  id: String,
  child: Spec(returning),
) -> StaticChild(DynamicSupervisorRef(returning)) {
  let start = fn() { kino.start_link(child) |> result.map(fn(s) { s.pid }) }
  let transform = fn(pid) { DynamicSupervisorRef(pid) }
  supervisor.supervisor_child(id, start)
  |> StaticChild(transform)
}

pub fn dynamic_child(
  spec: Spec(returning),
) -> DynamicChild(DynamicSupervisorRef(returning)) {
  DynamicChild(spec, DynamicSupervisorRef)
}

pub fn owner(supervisor: DynamicSupervisorRef(returning)) -> Pid {
  supervisor.pid
}

pub fn worker_children(owner: fn(returning) -> Pid) {
  dyn.worker_child("worker_child", fn(spec: kino.Spec(returning)) {
    kino.start_link(spec) |> result.map(owner)
  })
  |> dyn.new
  |> DynamicSupervisor
}

pub fn supervisor_children(owner: fn(returning) -> Pid) {
  dyn.supervisor_child("supervisor_child", fn(spec: kino.Spec(returning)) {
    kino.start_link(spec) |> result.map(owner)
  })
  |> dyn.new
  |> DynamicSupervisor
}
