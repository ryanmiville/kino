import gleam/erlang/process.{type Pid}
import kino/channel.{type Channel}
import kino/internal/atomic.{type AtomicInt}

type Done {
  Done
}

pub opaque type WaitGroup {
  WaitGroup(counter: AtomicInt, done: Channel(Done))
}

pub fn new() -> WaitGroup {
  WaitGroup(atomic.new(), channel.new())
}

fn incr(wg: WaitGroup) -> Nil {
  atomic.add(wg.counter, 1)
}

fn decr(wg: WaitGroup) -> Nil {
  case atomic.add_get(wg.counter, -1) {
    0 -> {
      let assert Ok(Nil) = channel.send(wg.done, Done)
      Nil
    }
    _ -> Nil
  }
}

pub fn spawn(wg: WaitGroup, running: fn() -> anything) -> Pid {
  incr(wg)
  process.start(linked: True, running: fn() {
    running()
    decr(wg)
  })
}

pub fn wait_forever(wg: WaitGroup) -> Nil {
  case atomic.get(wg.counter) {
    0 -> Nil
    _ -> wait_loop(wg)
  }
}

fn wait_loop(wg: WaitGroup) {
  let _ = channel.receive(wg.done)
  case atomic.get(wg.counter) {
    0 -> Nil
    _ -> wait_loop(wg)
  }
}
