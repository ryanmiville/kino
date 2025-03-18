import gleam/erlang/process
import gleam/otp/actor
import gleam/result
import lifeguard

pub opaque type Pool(a) {
  Pool(self: lifeguard.Pool(a))
}

pub opaque type WorkerSpec(state, message) {
  WorkerSpec(spec: lifeguard.Spec(state, message))
}

pub fn new(
  max_size: Int,
  worker_spec: WorkerSpec(state, msg),
) -> Result(Pool(msg), actor.StartError) {
  lifeguard.new(worker_spec.spec)
  |> lifeguard.with_size(max_size)
  |> lifeguard.start(1000)
  |> result.map(Pool)
  |> result.map_error(fn(error) {
    case error {
      lifeguard.PoolActorStartError(start_error) -> start_error
      lifeguard.WorkerStartError(start_error) -> start_error
      _ -> actor.InitTimeout
    }
  })
}

pub fn shutdown(pool: Pool(a)) {
  lifeguard.shutdown(pool.self)
}

pub fn worker(
  init: fn(process.Selector(a)) -> actor.InitResult(b, a),
  init_timeout: Int,
  loop: fn(a, b) -> actor.Next(a, b),
) -> WorkerSpec(b, a) {
  WorkerSpec(lifeguard.Spec(init:, init_timeout:, loop:))
}

pub fn send(pool: Pool(a), msg: a) -> Nil {
  case lifeguard.send(pool.self, msg, 5000) {
    Error(_) -> send(pool, msg)
    Ok(_) -> Nil
  }
}
