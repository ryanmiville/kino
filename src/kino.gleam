import gleam/dynamic
import gleam/erlang/process.{type Pid, type Subject}
import gleam/function
import gleam/otp/actor
import gleam/otp/static_supervisor as sup
import gleam/result
import gleam/string
import logging

pub type ActorRef(message) {
  ActorRef(subject: Subject(KinoMsg(message)), supervisor: Pid)
}

pub type StartError {
  ManagerStartError(actor.StartError)
  WorkerStartError(actor.StartError)
  WorkerSupervisorStartError(dynamic.Dynamic)
  SupervisorStartError(dynamic.Dynamic)
}

pub fn start(
  state: state,
  loop: fn(message, state) -> actor.Next(message, state),
) -> Result(ActorRef(message), StartError) {
  start_spec(actor.Spec(
    init: fn() { actor.Ready(state, process.new_selector()) },
    loop: loop,
    init_timeout: 5000,
  ))
}

pub fn start_spec(
  spec: actor.Spec(state, message),
) -> Result(ActorRef(message), StartError) {
  // let main_supervisor = sup.new(sup.OneForOne)
  let worker_supervisor = sup.new(sup.OneForOne)

  let manager =
    actor.start_spec(manager_spec(spec.init_timeout))
    |> result.map_error(ManagerStartError)

  use manager <- result.try(manager)

  // let worker =
  //   worker_spec(manager, spec)
  //   |> actor.start_spec
  //   |> result.map_error(WorkerStartError)

  // use worker <- result.try(worker)

  let worker_supervisor =
    sup.add(
      worker_supervisor,
      sup.worker_child("worker", fn() {
        let worker =
          actor.start_spec(spec)
          |> result.map_error(WorkerStartError)

        use worker <- result.map(worker)

        process.send(manager, Register(worker))
        process.subject_owner(worker)
      }),
    )
    |> sup.start_link()
    |> result.map_error(WorkerSupervisorStartError)

  use worker_supervisor <- result.map(worker_supervisor)

  // let main_supervisor =
  //   sup.add(
  //     main_supervisor,
  //     sup.worker_child("manager", fn() { process.subject_owner(manager) |> Ok })
  //       |> sup.restart(sup.Transient),
  //   )
  //   |> sup.add(
  //     sup.supervisor_child("worker_supervisor", fn() {
  //       worker_supervisor
  //       |> sup.start_link()
  //       |> result.map_error(WorkerSupervisorStartError)
  //       // Ok(worker_supervisor)
  //     }),
  //   )
  //   |> sup.start_link()
  //   |> result.map_error(SupervisorStartError)

  // use main_supervisor <- result.map(main_supervisor)

  process.unlink(worker_supervisor)
  // process.unlink(process.subject_owner(manager))
  ActorRef(subject: manager, supervisor: worker_supervisor)
}

pub fn send(ref: ActorRef(message), message: message) -> Nil {
  actor.send(ref.subject, Send(message))
}

pub fn call(
  ref: ActorRef(message),
  make_message: fn(Subject(reply)) -> message,
  timeout: Int,
) -> reply {
  process.call(ref.subject, make_kino_message(make_message), timeout)
}

pub fn try_call(
  ref: ActorRef(message),
  make_message: fn(Subject(reply)) -> message,
  within timeout: Int,
) -> Result(reply, process.CallError(reply)) {
  process.try_call(ref.subject, make_kino_message(make_message), timeout)
}

pub fn call_forever(
  ref: ActorRef(message),
  make_message: fn(Subject(reply)) -> message,
) -> reply {
  process.call_forever(ref.subject, make_kino_message(make_message))
}

pub fn try_call_forever(
  ref: ActorRef(message),
  make_message: fn(Subject(reply)) -> message,
) -> Result(reply, process.CallError(c)) {
  process.try_call_forever(ref.subject, make_kino_message(make_message))
}

pub type KinoMsg(message) {
  Register(worker_subject: Subject(message))
  Send(message)
  Ready
}

type State(message) {
  State(self: Subject(KinoMsg(message)), worker: Worker(message))
}

fn handle_kino_message(
  message: KinoMsg(resource_type),
  state: State(resource_type),
) {
  case message {
    Ready -> {
      logging.log(
        logging.Info,
        "Manager ready: " <> string.inspect(state.worker),
      )
      actor.continue(state)
    }
    Register(worker_subject:) -> {
      logging.log(
        logging.Info,
        "Registering worker: " <> string.inspect(worker_subject),
      )
      let worker = Worker(subject: worker_subject)
      handle_kino_message(Ready, State(..state, worker:))
    }
    Send(worker_msg) ->
      case state.worker {
        Worker(subject:) -> {
          logging.log(
            logging.Info,
            "sending message to worker: " <> string.inspect(subject),
          )
          actor.send(subject, worker_msg)
          actor.continue(state)
        }
        NotAvailable -> panic as "No worker available"
      }
  }
}

type Worker(message) {
  Worker(subject: Subject(message))
  NotAvailable
}

fn manager_spec(
  init_timeout: Int,
) -> actor.Spec(State(message), KinoMsg(message)) {
  actor.Spec(init_timeout:, loop: handle_kino_message, init: fn() {
    let self = process.new_subject()

    let selector =
      process.new_selector()
      |> process.selecting(self, function.identity)
    let state = State(self, NotAvailable)
    actor.Ready(state, selector)
  })
}

fn worker_spec(
  manager_subject: Subject(KinoMsg(message)),
  spec: actor.Spec(state, message),
) -> actor.Spec(state, message) {
  actor.Spec(init_timeout: spec.init_timeout, loop: spec.loop, init: fn() {
    let self = process.new_subject()
    process.send(manager_subject, Register(self))

    let selector =
      process.new_selector()
      |> process.selecting(self, function.identity)

    case spec.init() {
      actor.Failed(_) as failed -> failed
      actor.Ready(state, old_selector) -> {
        let selector = process.merge_selector(old_selector, selector)
        actor.Ready(state, selector)
      }
    }
  })
}

fn make_kino_message(
  make_message: fn(Subject(reply)) -> message,
) -> fn(Subject(reply)) -> KinoMsg(message) {
  fn(reply_to) { Send(make_message(reply_to)) }
}
