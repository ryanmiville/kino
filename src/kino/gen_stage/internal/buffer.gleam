import gleam/bool
import gleam/deque
import gleam/list
import gleam/option.{type Option, None, Some}

pub type Buffer(event) {
  Buffer(queue: deque.Deque(event), counter: Int)
}

pub fn new() -> Buffer(event) {
  Buffer(deque.new(), 0)
}

pub fn store(buffer: Buffer(event), events: List(event)) -> Buffer(event) {
  case events {
    [] -> buffer
    [event, ..rest] ->
      store(
        Buffer(deque.push_back(buffer.queue, event), buffer.counter + 1),
        rest,
      )
  }
}

pub fn estimate_count(buffer: Buffer(event)) -> Int {
  buffer.counter
}

pub type Take(event) {
  Take(buffer: Buffer(event), counter: Int, events: List(event))
}

pub fn take(buffer: Buffer(event), counter: Int) -> Take(event) {
  do_take(counter, [], buffer)
}

fn do_take(
  counter: Int,
  events: List(event),
  buffer: Buffer(event),
) -> Take(event) {
  use <- bool.lazy_guard(counter == 0, fn() {
    Take(buffer, counter, list.reverse(events))
  })

  case deque.pop_front(buffer.queue) {
    Error(Nil) ->
      Take(Buffer(..buffer, counter: 0), counter, list.reverse(events))

    Ok(#(event, queue)) ->
      do_take(
        counter - 1,
        [event, ..events],
        Buffer(queue: queue, counter: buffer.counter - 1),
      )
  }
}
