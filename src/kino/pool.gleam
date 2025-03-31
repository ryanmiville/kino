import gleam/erlang/process.{type Pid}
import kino/channel.{type Channel}
import kino/internal/atomic.{type AtomicInt}
import kino/waitgroup.{type WaitGroup}

pub opaque type Pool {
  Pool(
    handle: WaitGroup,
    limiter: AtomicInt,
    tasks: Channel(fn() -> Nil),
    max_size: Int,
    owner: Pid,
  )
}

pub fn new(max_size: Int) {
  Pool(
    handle: waitgroup.new(),
    limiter: atomic.new(),
    tasks: channel.with_capacity(max_size),
    max_size: max_size,
    owner: process.self(),
  )
}

pub fn spawn(pool: Pool, running: fn() -> anything) -> Nil {
  case atomic.get(pool.limiter) < pool.max_size {
    True -> {
      atomic.add(pool.limiter, 1)
      waitgroup.spawn(pool.handle, fn() { worker(pool, running) })
      Nil
    }
    False -> {
      let assert Ok(_) =
        channel.send(pool.tasks, fn() {
          running()
          Nil
        })
      Nil
    }
  }
}

pub fn wait_forever(pool: Pool) -> Nil {
  assert_owner(pool)
  channel.close(pool.tasks)
  waitgroup.wait_forever(pool.handle)
}

fn worker(pool: Pool, running: fn() -> anything) -> channel.Closed {
  running()
  channel.each(pool.tasks, fn(f) { f() })
}

fn assert_owner(pool: Pool) {
  let assert True = pool.owner == process.self()
    as "waited on a pool that doesn not belong to this process"
  Nil
}
