import gleam/deque.{type Deque}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/set.{type Set}
import kino/actor.{type ActorRef, type Behavior}
import kino/dynamic_supervisor.{type DynamicSupervisorRef} as dyn
import kino/supervisor.{type SupervisorRef}
import ppool/worker
import ppool/worker_sup

type ReplyTo =
  Subject(Result(ActorRef(worker.Message), NoAlloc))

type Item {
  SyncItem(reply_to: ReplyTo, args: worker.State)
  AsyncItem(args: worker.State)
}

pub type Message {
  StartWorkerSupervisor
  Run(args: worker.State, reply_to: ReplyTo)
  Sync(args: worker.State, reply_to: ReplyTo)
  Async(args: worker.State)
  WorkerDown(worker: ActorRef(worker.Message))
  Stop
}

pub fn spec(
  limit: Int,
  sup: SupervisorRef,
  ack: Subject(ActorRef(Message)),
) -> actor.Spec(Message) {
  use self <- actor.init()
  actor.send(self, StartWorkerSupervisor)
  process.send(ack, self)
  setup(limit, sup)
}

fn setup(limit: Int, sup: SupervisorRef) -> Behavior(Message) {
  use _, message <- actor.receive()
  case message {
    StartWorkerSupervisor -> {
      let child =
        supervisor.supervisor_child("worker_supervisor", worker_sup.spec())
      let assert Ok(worker_sup) = supervisor.start_child(sup, child)
      process.link(dyn.owner(worker_sup))

      loop(State(limit, worker_sup, set.new(), deque.new()))
    }
    _ -> panic as "actor is not ready"
  }
}

type WorkerSup =
  DynamicSupervisorRef(ActorRef(worker.Message))

pub type NoAlloc {
  NoAlloc
}

type State {
  State(
    limit: Int,
    worker_sup: WorkerSup,
    refs: Set(ActorRef(worker.Message)),
    queue: Deque(Item),
  )
}

fn loop(state: State) -> Behavior(Message) {
  use _, message <- actor.receive()
  case message {
    Run(args:, reply_to:) -> {
      case has_space(state.limit) {
        True -> run_sync(state, args, reply_to)
        False -> noalloc(reply_to)
      }
    }

    Sync(args:, reply_to:) -> {
      case has_space(state.limit) {
        True -> run_sync(state, args, reply_to)
        False -> add_sync(state, args, reply_to)
      }
    }

    Async(args:) -> {
      case has_space(state.limit) {
        True -> run_async(state, args)
        False -> add_async(state, args)
      }
    }

    WorkerDown(worker:) -> {
      io.println("Entering worker down")
      case set.contains(state.refs, worker) {
        True -> down_worker(state, worker)
        False -> actor.continue
      }
    }

    Stop -> actor.stopped

    StartWorkerSupervisor -> actor.continue
  }
}

fn run_sync(state: State, args, reply_to) {
  let assert Ok(worker) = dyn.start_child(state.worker_sup, worker.spec(args))
  process.send(reply_to, Ok(worker))
  let refs = set.insert(state.refs, worker)
  let limit = state.limit - 1

  loop(State(..state, limit:, refs:))
  |> actor.monitoring(actor.owner(worker), fn(_) { WorkerDown(worker) })
}

fn add_sync(state: State, args, reply_to) {
  let queue = deque.push_back(state.queue, SyncItem(reply_to, args))
  loop(State(..state, queue:))
}

fn add_async(state: State, args) {
  let queue = deque.push_back(state.queue, AsyncItem(args))
  loop(State(..state, queue:))
}

fn noalloc(reply_to) {
  process.send(reply_to, Error(NoAlloc))
  actor.continue
}

fn run_async(state: State, args) {
  let assert Ok(worker) = dyn.start_child(state.worker_sup, worker.spec(args))
  let refs = set.insert(state.refs, worker)
  let limit = state.limit - 1

  loop(State(..state, limit:, refs:))
  |> actor.monitoring(actor.owner(worker), fn(_) { WorkerDown(worker) })
}

fn has_space(limit) {
  io.println("current space: " <> int.to_string(limit))
  limit > 0
}

fn down_worker(state: State, worker) {
  let refs = set.delete(state.refs, worker)

  case deque.pop_front(state.queue) {
    Ok(#(SyncItem(reply_to, args), queue)) ->
      run_sync(
        State(..state, refs:, queue:, limit: state.limit + 1),
        args,
        reply_to,
      )

    Ok(#(AsyncItem(args), queue)) ->
      run_async(State(..state, refs:, queue:, limit: state.limit + 1), args)

    Error(_) -> loop(State(..state, refs:, limit: state.limit + 1))
  }
}
