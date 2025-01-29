import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Pid}
import gleam/pair
import gleam/result
import kino
import kino/child.{type Child, Child}
import kino/internal/dynamic_supervisor as dyn
import kino/internal/supervisor

pub type Spec(returning) =
  kino.Spec(DynamicSupervisorRef(returning))

pub opaque type DynamicSupervisorRef(returning) {
  DynamicSupervisorRef(pid: Pid)
}

pub type DynamicSupervisor(returning) {
  DynamicSupervisor(builder: dyn.Builder(kino.Spec(returning), returning))
}

pub fn init(
  init: fn(DynamicSupervisorRef(returning)) -> DynamicSupervisor(returning),
) -> Spec(returning) {
  fn() {
    init(DynamicSupervisorRef(process.self())).builder
    |> dyn.start_link
    |> result.map(dyn.owner)
    |> result.map(fn(pid) { #(pid, DynamicSupervisorRef(pid)) })
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
  child: kino.Spec(returning),
) -> Result(returning, Dynamic) {
  dyn.start_child(dyn.from_pid(ref.pid), child)
  |> result.map(pair.second)
}

pub fn child_spec(
  id: String,
  child: Spec(returning),
) -> Child(DynamicSupervisorRef(returning)) {
  let start = fn() {
    use ref <- result.map(kino.start_link(child))
    #(ref.pid, ref)
  }
  Child(supervisor.supervisor_child(id, start))
}

pub fn owner(supervisor: DynamicSupervisorRef(returning)) -> Pid {
  supervisor.pid
}

pub fn worker_children() {
  dyn.worker_child("worker_child", fn(spec: kino.Spec(returning)) {
    spec.init()
  })
  |> dyn.new
  |> DynamicSupervisor
}

pub fn supervisor_children() {
  dyn.supervisor_child("supervisor_child", fn(spec: kino.Spec(returning)) {
    spec.init()
  })
  |> dyn.new
  |> DynamicSupervisor
}
