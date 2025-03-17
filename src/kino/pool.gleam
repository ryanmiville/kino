import gleam/deque.{type Deque}
import gleam/erlang/process.{type Subject}
import gleam/function
import gleam/otp/actor

pub opaque type Pool(a) {
  Pool(self: Subject(Message(a)))
}

pub fn new(max_size: Int) {
  Pool(start_pool(max_size))
}

pub fn send(pool: Pool(a), f: fn() -> a) -> Subject(a) {
  let subject = process.new_subject()
  process.send(pool.self, Send(f, subject))
  subject
}

pub fn stop(pool: Pool(a)) -> Nil {
  process.send(pool.self, Stop)
}

type Message(a) {
  Available(Subject(WorkerMessage(a)))
  Send(fn() -> a, Subject(a))
  Stop
}

type State(a) {
  State(
    self: Subject(Message(a)),
    max_size: Int,
    count: Int,
    available: List(Subject(WorkerMessage(a))),
    queue: Deque(WorkerMessage(a)),
  )
}

fn start_pool(max_size: Int) {
  let init = fn() {
    let self = process.new_subject()
    let sel =
      process.new_selector()
      |> process.selecting(self, function.identity)
    State(self:, max_size:, count: 0, available: [], queue: deque.new())
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
    Send(f, reply_to) -> {
      case state.available {
        [worker, ..rest] -> {
          process.send(worker, WorkerMessage(f, reply_to))
          State(..state, available: rest) |> actor.continue
        }
        [] if state.count < state.max_size -> {
          let worker = new_worker(state.self)
          process.send(worker, WorkerMessage(f, reply_to))
          State(..state, count: state.count + 1) |> actor.continue
        }
        [] -> {
          let queue = deque.push_back(state.queue, WorkerMessage(f, reply_to))
          State(..state, queue:) |> actor.continue
        }
      }
    }
    // Await(reply_to) if state.available_count == state.count -> {
    //   todo
    // }
    // Await(_reply_to) -> {
    //   process.send(state.self, msg)
    //   actor.continue(state)
    // }
    Stop -> {
      actor.Stop(process.Normal)
    }
  }
}

fn new_worker(pool) -> Subject(WorkerMessage(a)) {
  let init = fn() {
    let self = process.new_subject()
    let sel =
      process.new_selector()
      |> process.selecting(self, function.identity)
    actor.Ready(Worker(self, pool), sel)
  }
  let assert Ok(worker) =
    actor.start_spec(actor.Spec(init, 1000, worker_on_message))
  worker
}

type Worker(a) {
  Worker(self: Subject(WorkerMessage(a)), pool: Subject(Message(a)))
}

type WorkerMessage(a) {
  WorkerMessage(f: fn() -> a, reply_to: Subject(a))
}

fn worker_on_message(msg: WorkerMessage(a), worker: Worker(a)) {
  process.send(msg.reply_to, msg.f())
  process.send(worker.pool, Available(worker.self))
  actor.continue(worker)
}
