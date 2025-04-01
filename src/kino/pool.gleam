import kino/channel.{type Channel}
import kino/internal/atomic.{type AtomicInt}
import kino/waitgroup.{type WaitGroup}

pub opaque type Pool {
  Pool(
    handle: WaitGroup,
    limiter: AtomicInt,
    tasks: Channel(fn() -> Nil),
    max_size: Int,
  )
}

pub fn new(max_size: Int) {
  Pool(
    handle: waitgroup.new(),
    limiter: atomic.new(),
    tasks: channel.with_capacity(max_size),
    max_size: max_size,
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
  channel.close(pool.tasks)
  waitgroup.wait_forever(pool.handle)
}

fn worker(pool: Pool, running: fn() -> anything) -> channel.Closed {
  running()
  channel.each(pool.tasks, fn(f) { f() })
}
