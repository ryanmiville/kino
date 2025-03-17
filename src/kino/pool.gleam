import gleam/deque.{type Deque}
import gleam/erlang/process.{type Subject}
import gleam/function
import gleam/otp/actor

pub opaque type Pool {
  Pool(self: Subject(Message))
}

pub fn new(max_size: Int) {
  Pool(start_pool(max_size))
}

pub fn send(pool: Pool, f: fn() -> Nil) -> Nil {
  process.send(pool.self, Send(f, process.new_subject()))
}

pub fn stop(pool: Pool) -> Nil {
  process.send(pool.self, Stop)
}

type Message {
  Available(Subject(fn() -> Nil))
  Send(fn() -> Nil, Subject(Nil))
  Stop
}

type State {
  State(
    self: Subject(Message),
    max_size: Int,
    count: Int,
    available: List(Subject(fn() -> Nil)),
    queue: Deque(fn() -> Nil),
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

fn on_message(msg: Message, state: State) {
  case msg {
    Available(worker) -> {
      case deque.pop_front(state.queue) {
        Ok(#(work, queue)) -> {
          process.send(worker, work)
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
          process.send(worker, f)
          State(..state, available: rest) |> actor.continue
        }
        [] if state.count < state.max_size -> {
          let worker = new_worker(state.self)
          process.send(worker, f)
          process.send(reply_to, Nil)
          State(..state, count: state.count + 1) |> actor.continue
        }
        [] -> {
          let queue = deque.push_back(state.queue, f)
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

fn new_worker(pool) {
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

type Worker {
  Worker(self: Subject(fn() -> Nil), pool: Subject(Message))
}

fn worker_on_message(f: fn() -> Nil, worker: Worker) {
  f()
  process.send(worker.pool, Available(worker.self))
  actor.continue(worker)
}
