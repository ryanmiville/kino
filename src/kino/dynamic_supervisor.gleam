import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Pid}
import gleam/pair
import gleam/result
import kino
import kino/internal/dynamic_supervisor as dyn

pub type Spec(returning) =
  kino.Spec(DynamicSupervisorRef(returning))

pub opaque type DynamicSupervisorRef(returning) {
  DynamicSupervisorRef(pid: Pid)
}

pub type Restart {
  /// A permanent child process is always restarted.
  Permanent
  /// A transient child process is restarted only if it terminates abnormally,
  /// that is, with another exit reason than `normal`, `shutdown`, or
  /// `{shutdown,Term}`.
  Transient
  /// A temporary child process is never restarted (even when the supervisor's
  /// restart strategy is `RestForOne` or `OneForAll` and a sibling's death
  /// causes the temporary process to be terminated).
  Temporary
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

pub fn owner(supervisor: DynamicSupervisorRef(returning)) -> Pid {
  supervisor.pid
}

pub fn worker_children(restart: Restart) {
  dyn.worker_child("worker_child", fn(spec: kino.Spec(returning)) {
    spec.init()
  })
  |> set_restart(restart)
  |> dyn.new
  |> DynamicSupervisor
}

pub fn supervisor_children(restart: Restart) {
  dyn.supervisor_child("supervisor_child", fn(spec: kino.Spec(returning)) {
    spec.init()
  })
  |> set_restart(restart)
  |> dyn.new
  |> DynamicSupervisor
}

fn set_restart(child, restart) {
  let restart = case restart {
    Permanent -> dyn.Permanent
    Temporary -> dyn.Temporary
    Transient -> dyn.Transient
  }
  dyn.restart(child, restart)
}
