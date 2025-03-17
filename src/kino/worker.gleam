import gleam/erlang/process.{type Pid, type Subject}
import gleam/otp/actor

pub opaque type Worker(in, out) {
  Worker(owner: Pid, owner_subject: Subject(out), self_subject: Subject(in))
}

pub fn new(work: fn(in) -> out) -> Worker(in, out) {
  let owner = process.self()
  let owner_subject = process.new_subject()
  let self_subject = start(State(work, owner_subject))
  Worker(owner, owner_subject, self_subject)
}

pub fn async(worker: Worker(in, out), input: in) {
  assert_owner(worker)
  process.send(worker.self_subject, input)
}

pub fn await(worker: Worker(in, out), timeout: Int) {
  process.receive(worker.owner_subject, timeout)
}

pub fn await_forever(worker: Worker(in, out)) {
  process.receive_forever(worker.owner_subject)
}

// We can only wait on a task if we are the owner of it so crash if we are
// waiting on a task we don't own.
fn assert_owner(worker: Worker(in, out)) -> Nil {
  let self = process.self()
  case worker.owner == self {
    True -> Nil
    False ->
      process.send_abnormal_exit(
        self,
        "awaited on a worker that does not belong to this process",
      )
  }
}

type State(in, out) {
  State(work: fn(in) -> out, owner: Subject(out))
}

fn start(state: State(in, out)) -> Subject(in) {
  let assert Ok(subject) = actor.start(state, on_message)
  subject
}

fn on_message(input: in, state: State(in, out)) -> actor.Next(a, State(in, out)) {
  let output = state.work(input)
  process.send(state.owner, output)
  actor.continue(state)
}
