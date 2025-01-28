//// Bindings to the Erlang/OTP's `supervisor` module's `simple_one_for_one`
//// strategy.
////
//// For further detail see the Erlang documentation:
//// <https://www.erlang.org/doc/apps/stdlib/supervisor.html>.
////
//// # Example
////
//// ```gleam
//// import gleam/erlang/process.{type Pid}
//// import gleam/otp/dynamic_supervisor as sup
////
//// pub fn start_supervisor() {
////   let assert Ok(supervisor) =
////     sup.new(sup.worker_child("worker", start_worker))
////     |> sup.start_link
////
////   let assert Ok(p1) =  sup.start_child(supervisor, "1")
////   let assert Ok(p2) =  sup.start_child(supervisor, "2")
//// }
////
//// fn start_worker(args) -> Result(Pid, error) {
////  // Start a worker process
//// }
//// ```

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type Pid}
import gleam/result

type SimpleOneForOne {
  SimpleOneForOne
}

/// A supervisor can be configured to automatically shut itself down with exit
/// reason shutdown when significant children terminate with the auto_shutdown
/// key in the above map.
pub type AutoShutdown {
  /// Automic shutdown is disabled. This is the default setting.
  ///
  /// With auto_shutdown set to never, child specs with the significant flag
  /// set to true are considered invalid and will be rejected.
  Never
  /// The supervisor will shut itself down when any significant child
  /// terminates, that is, when a transient significant child terminates
  /// normally or when a temporary significant child terminates normally or
  /// abnormally.
  AnySignificant
  /// The supervisor will shut itself down when all significant children have
  /// terminated, that is, when the last active significant child terminates.
  /// The same rules as for any_significant apply.
  AllSignificant
}

pub opaque type Builder(args) {
  Builder(
    intensity: Int,
    period: Int,
    auto_shutdown: AutoShutdown,
    child: ChildBuilder(args),
  )
}

pub fn new(child: ChildBuilder(args)) -> Builder(args) {
  Builder(intensity: 2, period: 5, auto_shutdown: Never, child:)
}

/// To prevent a supervisor from getting into an infinite loop of child
/// process terminations and restarts, a maximum restart intensity is
/// defined using two integer values specified with keys intensity and
/// period in the above map. Assuming the values MaxR for intensity and MaxT
/// for period, then, if more than MaxR restarts occur within MaxT seconds,
/// the supervisor terminates all child processes and then itself. The
/// termination reason for the supervisor itself in that case will be
/// shutdown.
///
/// Intensity defaults to 1 and period defaults to 5.
pub fn restart_tolerance(
  builder: Builder(args),
  intensity intensity: Int,
  period period: Int,
) -> Builder(args) {
  Builder(..builder, intensity: intensity, period: period)
}

/// A supervisor can be configured to automatically shut itself down with
/// exit reason shutdown when significant children terminate.
pub fn auto_shutdown(
  builder: Builder(args),
  value: AutoShutdown,
) -> Builder(args) {
  Builder(..builder, auto_shutdown: value)
}

/// Restart defines when a terminated child process must be restarted.
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

pub type ChildType {
  Worker(
    /// The number of milliseconds the child is given to shut down. The
    /// supervisor tells the child process to terminate by calling
    /// `exit(Child,shutdown)` and then wait for an exit signal with reason
    /// shutdown back from the child process. If no exit signal is received
    /// within the specified number of milliseconds, the child process is
    /// unconditionally terminated using `exit(Child,kill)`.
    shutdown_ms: Int,
  )
  Supervisor
}

pub opaque type ChildBuilder(args) {
  ChildBuilder(
    /// id is used to identify the child specification internally by the
    /// supervisor.
    ///
    /// Notice that this identifier on occations has been called "name". As far
    /// as possible, the terms "identifier" or "id" are now used but to keep
    /// backward compatibility, some occurences of "name" can still be found, for
    /// example in error messages.
    id: String,
    /// A function to call to start the child process.
    starter: fn(args) -> Result(Pid, Dynamic),
    /// When the child is to be restarted. See the `Restart` documentation for
    /// more.
    ///
    /// You most likely want the `Permanent` variant.
    restart: Restart,
    /// This defines if a child is considered significant for automatic
    /// self-shutdown of the supervisor.
    ///
    /// You most likely do not want to consider any children significant.
    ///
    /// This will be ignored if the supervisor auto shutdown is set to `Never`,
    /// which is the default.
    significant: Bool,
    /// Whether the child is a supervisor or not.
    child_type: ChildType,
  )
}

/// A `DynamicSupervisor` represents a supervisor process that can start a new
/// child process in a well typed way.
///
/// # Examples
///
/// ```gleam
/// let sup_1: DynamicSupervisor(String) = todo
/// let sup_2: DynamicSupervisor(Int) = todo
/// let sup_3: DynamicSupervisor(#(String, Int)) = todo
///
/// let assert Ok(p1) = sup.start_child(sup_1, "Hello, Joe!")
/// let assert Ok(p2) = sup.start_child(sup_2, 42)
/// let assert Ok(p3) = sup.start_child(sup_3, #("Hello, Joe!", 42))
/// ```
///
pub opaque type DynamicSupervisor(args) {
  DynamicSupervisor(pid: Pid)
}

/// Get the owner process of the supervisor
///
pub fn owner(supervisor: DynamicSupervisor(args)) -> Pid {
  supervisor.pid
}

// TODO this is a hack
pub fn self() -> DynamicSupervisor(args) {
  DynamicSupervisor(process.self())
}

// TODO this is a hack
pub fn from_pid(pid: Pid) -> DynamicSupervisor(args) {
  DynamicSupervisor(pid)
}

pub fn start_link(
  builder: Builder(args),
) -> Result(DynamicSupervisor(args), Dynamic) {
  let flags =
    dict.new()
    |> property("strategy", SimpleOneForOne)
    |> property("intensity", builder.intensity)
    |> property("period", builder.period)
    |> property("auto_shutdown", builder.auto_shutdown)

  let child = convert_child(builder.child)

  let module = atom.create_from_string("kino@internal@dynamic_supervisor")

  erlang_start_link(module, #(flags, [child]))
  |> result.map(DynamicSupervisor)
}

@external(erlang, "supervisor", "start_link")
fn erlang_start_link(
  module: Atom,
  args: #(Dict(Atom, Dynamic), List(Dict(Atom, Dynamic))),
) -> Result(Pid, Dynamic)

/// Dynamically starts a child process under the supervisor, passing `args` to
/// the child's `start` function.
///
pub fn start_child(
  supervisor: DynamicSupervisor(args),
  args: args,
) -> Result(Pid, Dynamic) {
  erlang_start_child(supervisor.pid, [[args]])
}

@external(erlang, "supervisor", "start_child")
fn erlang_start_child(
  supervisor: Pid,
  args: List(List(args)),
) -> Result(Pid, Dynamic)

/// A regular child that is not also a supervisor.
///
/// id is used to identify the child specification internally by the
/// supervisor.
/// Notice that this identifier on occations has been called "name". As far
/// as possible, the terms "identifier" or "id" are now used but to keep
/// backward compatibility, some occurences of "name" can still be found, for
/// example in error messages.
///
pub fn worker_child(
  id id: String,
  run starter: fn(args) -> Result(Pid, whatever),
) -> ChildBuilder(args) {
  ChildBuilder(
    id: id,
    starter: fn(args: args) { starter(args) |> result.map_error(dynamic.from) },
    restart: Permanent,
    significant: False,
    child_type: Worker(5000),
  )
}

/// A special child that is a supervisor itself.
///
/// id is used to identify the child specification internally by the
/// supervisor.
/// Notice that this identifier on occations has been called "name". As far
/// as possible, the terms "identifier" or "id" are now used but to keep
/// backward compatibility, some occurences of "name" can still be found, for
/// example in error messages.
///
pub fn supervisor_child(
  id id: String,
  run starter: fn(args) -> Result(Pid, whatever),
) -> ChildBuilder(args) {
  ChildBuilder(
    id: id,
    starter: fn(args) { starter(args) |> result.map_error(dynamic.from) },
    restart: Permanent,
    significant: False,
    child_type: Supervisor,
  )
}

/// This defines if a child is considered significant for automatic
/// self-shutdown of the supervisor.
///
/// You most likely do not want to consider any children significant.
///
/// This will be ignored if the supervisor auto shutdown is set to `Never`,
/// which is the default.
///
/// The default value for significance is `False`.
pub fn significant(
  child: ChildBuilder(args),
  significant: Bool,
) -> ChildBuilder(args) {
  ChildBuilder(..child, significant: significant)
}

/// This defines the amount of milliseconds a child has to shut down before
/// being brutal killed by the supervisor.
///
/// If not set the default for a child is 5000ms.
///
/// This will be ignored if the child is a supervisor itself.
///
pub fn timeout(child: ChildBuilder(args), ms ms: Int) -> ChildBuilder(args) {
  case child.child_type {
    Worker(_) -> ChildBuilder(..child, child_type: Worker(ms))
    _ -> child
  }
}

/// When the child is to be restarted. See the `Restart` documentation for
/// more.
///
/// The default value for restart is `Permanent`.
pub fn restart(
  child: ChildBuilder(args),
  restart: Restart,
) -> ChildBuilder(args) {
  ChildBuilder(..child, restart: restart)
}

fn convert_child(child: ChildBuilder(args)) -> Dict(Atom, Dynamic) {
  let mfa = #(
    atom.create_from_string("erlang"),
    atom.create_from_string("apply"),
    [dynamic.from(child.starter)],
  )

  // pub fn dynamic_child(
  //   starter: fn(init_arg) -> Spec(message),
  // ) -> DynamicChild(init_arg, ActorRef(message)) {
  //   let start = fn(arg) { starter(arg).init() |> result.map(owner) }

  //   let child = dyn.worker_child("", start)
  //   DynamicChild(child, fn(pid) { ActorRef(gen_server.from_pid(pid)) })
  // }

  let #(type_, shutdown) = case child.child_type {
    Supervisor -> #(
      atom.create_from_string("supervisor"),
      dynamic.from(atom.create_from_string("infinity")),
    )
    Worker(timeout) -> #(
      atom.create_from_string("worker"),
      dynamic.from(timeout),
    )
  }

  dict.new()
  |> property("id", child.id)
  |> property("start", mfa)
  |> property("restart", child.restart)
  |> property("significant", child.significant)
  |> property("type", type_)
  |> property("shutdown", shutdown)
}

fn property(
  dict: Dict(Atom, Dynamic),
  key: String,
  value: anything,
) -> Dict(Atom, Dynamic) {
  dict.insert(dict, atom.create_from_string(key), dynamic.from(value))
}

// Callback used by the Erlang supervisor module.
@internal
pub fn init(start_data: Dynamic) -> Result(Dynamic, never) {
  Ok(start_data)
}
