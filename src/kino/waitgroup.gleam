import gleam/erlang/process.{type Pid, type Subject}
import kino/internal/atomic.{type AtomicInt}

type Done {
  Done
}

pub opaque type WaitGroup {
  WaitGroup(counter: AtomicInt, self: Subject(Done))
}

pub fn new() -> WaitGroup {
  WaitGroup(atomic.new(), process.new_subject())
}

fn incr(wg: WaitGroup) -> Nil {
  atomic.add(wg.counter, 1)
}

fn decr(wg: WaitGroup) -> Nil {
  case atomic.add_get(wg.counter, -1) {
    0 -> process.send(wg.self, Done)
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
  let _ = process.receive_forever(wg.self)
  case atomic.get(wg.counter) {
    0 -> Nil
    _ -> wait_forever(wg)
  }
}
