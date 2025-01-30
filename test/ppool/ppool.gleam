import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Subject}
import gleam/result
import kino/actor.{type ActorRef}
import kino/dynamic_supervisor.{type DynamicSupervisorRef} as dyn
import kino/supervisor.{type SupervisorRef}
import ppool/serv
import ppool/sup
import ppool/supersup
import ppool/worker

pub opaque type Supervisor {
  Supervisor(ref: DynamicSupervisorRef(SupervisorRef))
}

pub opaque type Pool {
  Pool(ref: ActorRef(serv.Message))
}

pub fn start_link() -> Result(Supervisor, Dynamic) {
  dyn.start_link(supersup.spec()) |> result.map(Supervisor)
}

pub fn start_pool(super: Supervisor, limit: Int) -> Result(Pool, Dynamic) {
  let self = process.new_subject()
  let sup = dyn.start_child(super.ref, sup.spec(limit, self))
  use _ <- result.try(sup)
  process.receive(self, 100)
  |> result.map(Pool)
  |> result.map_error(fn(_) { dynamic.from("failed to receieve pool") })
}

pub fn run(
  pool pool: Pool,
  task task: String,
  delay delay: Int,
  max max: Int,
  reply_to reply_to: Subject(String),
) -> Result(
  Result(ActorRef(worker.Message), serv.NoAlloc),
  process.CallError(Result(ActorRef(worker.Message), serv.NoAlloc)),
) {
  let args = worker.State(task:, delay:, max:, reply_to:)
  actor.try_call(pool.ref, serv.Run(args, _), 5000)
}

pub fn async_queue(
  pool pool: Pool,
  task task: String,
  delay delay: Int,
  max max: Int,
  reply_to reply_to: Subject(String),
) -> Nil {
  let args = worker.State(task:, delay:, max:, reply_to:)
  actor.send(pool.ref, serv.Async(args))
}

pub fn sync_queue(
  pool pool: Pool,
  task task: String,
  delay delay: Int,
  max max: Int,
  reply_to reply_to: Subject(String),
) -> Result(ActorRef(worker.Message), serv.NoAlloc) {
  let args = worker.State(task:, delay:, max:, reply_to:)
  actor.call_forever(pool.ref, serv.Sync(args, _))
}
