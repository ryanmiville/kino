import gleam/deque.{type Deque}
import gleam/erlang/process.{type Pid, type Subject}
import gleam/function
import gleam/otp/actor

pub opaque type Pool(a) {
  Pool(self: Subject(Message(a)), pid: Pid, owner: Subject(a))
}

pub fn new(max_size: Int, worker: actor.Spec(state, msg)) {
  let owner = process.new_subject()
  Pool(start_pool(max_size, worker), process.self(), owner)
}

pub fn send(pool: Pool(a), message: a) -> Nil {
  process.send(pool.self, Send(message))
}

pub fn stop(pool: Pool(a)) -> Nil {
  process.send(pool.self, Stop)
}

type Message(a) {
  Available(Subject(a))
  Send(a)
  Stop
}

type State(a) {
  State(
    self: Subject(Message(a)),
    start_worker: fn() -> Subject(a),
    max_size: Int,
    count: Int,
    available: List(Subject(a)),
    queue: Deque(a),
  )
}

fn start_pool(max_size: Int, spec: actor.Spec(state, msg)) {
  let init = fn() {
    let self = process.new_subject()
    let sel =
      process.new_selector()
      |> process.selecting(self, function.identity)

    let start_worker = fn() { new_worker(self, spec) }

    State(
      self:,
      start_worker:,
      max_size:,
      count: 0,
      available: [],
      queue: deque.new(),
    )
    |> actor.Ready(sel)
  }
  let assert Ok(pool) = actor.start_spec(actor.Spec(init, 1000, on_message))
  pool
}

fn on_message(msg: Message(a), state: State(a)) {
  case msg {
    Available(worker) -> {
      case deque.pop_front(state.queue) {
        Ok(#(worker_message, queue)) -> {
          process.send(worker, worker_message)
          State(..state, queue:) |> actor.continue
        }
        Error(_) -> {
          let available = [worker, ..state.available]
          State(..state, available:) |> actor.continue
        }
      }
    }
    Send(msg) -> {
      case state.available {
        [worker, ..rest] -> {
          process.send(worker, msg)
          State(..state, available: rest) |> actor.continue
        }
        [] if state.count < state.max_size -> {
          let worker = state.start_worker()
          process.send(worker, msg)
          State(..state, count: state.count + 1) |> actor.continue
        }
        [] -> {
          let queue = deque.push_back(state.queue, msg)
          State(..state, queue:) |> actor.continue
        }
      }
    }
    Stop -> {
      actor.Stop(process.Normal)
    }
  }
}

fn new_worker(
  pool: Subject(Message(msg)),
  spec: actor.Spec(state, msg),
) -> Subject(msg) {
  let init = fn() {
    case spec.init() {
      actor.Failed(err) -> actor.Failed(err)
      actor.Ready(state, selector) -> {
        let self = process.new_subject()
        let selector = process.selecting(selector, self, function.identity)
        Worker(self:, pool:, on_message: spec.loop, state:)
        |> actor.Ready(selector)
      }
    }
  }
  let assert Ok(worker) =
    actor.start_spec(actor.Spec(init, spec.init_timeout, worker_on_message))
  worker
}

type Worker(msg, state) {
  Worker(
    self: Subject(msg),
    pool: Subject(Message(msg)),
    on_message: fn(msg, state) -> actor.Next(msg, state),
    state: state,
  )
}

fn worker_on_message(message: message, worker: Worker(message, state)) {
  case worker.on_message(message, worker.state) {
    actor.Continue(new_state, sel) -> {
      process.send(worker.pool, Available(worker.self))
      let worker = Worker(..worker, state: new_state)
      actor.Continue(worker, sel)
    }
    actor.Stop(reason) -> actor.Stop(reason)
  }
}
