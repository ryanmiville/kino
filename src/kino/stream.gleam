import gleam/dynamic.{type Dynamic}
import gleam/erlang/process
import gleam/list
import gleam/otp/actor
import gleam/result
import kino/sink.{type Sink}
import kino/source.{type Source, Source}

const default_max_demand = 1000

type Action(element) {
  Continue(List(element), fn(Int) -> Action(element))
  Stop
}

pub opaque type Stream(element) {
  Stream(continuation: fn(Int) -> Action(element))
}

// Public API for iteration
pub type Step(element, accumulator) {
  Next(elements: List(element), accumulator: accumulator)
  Done
}

pub type Consume(accumulator) {
  Consume(accumulator)
  Complete
}

pub fn unfold(
  from initial: state,
  with demand_handler: fn(state, Int) -> Step(element, state),
) -> Stream(element) {
  initial
  |> do_unfold(demand_handler)
  |> Stream
}

fn do_unfold(
  initial: acc,
  f: fn(acc, Int) -> Step(element, acc),
) -> fn(Int) -> Action(element) {
  fn(demand) {
    case f(initial, demand) {
      Next(x, acc) -> Continue(x, do_unfold(acc, f))
      Done -> Stop
    }
  }
}

pub fn repeatedly(f: fn() -> element) -> Stream(element) {
  unfold(Nil, fn(_, _) { Next([f()], Nil) })
}

pub fn repeat(x: element) -> Stream(element) {
  repeatedly(fn() { x })
}

pub fn from_list(list: List(element)) -> Stream(element) {
  let handler = fn(acc, _demand) {
    case acc {
      [] -> Done
      _ -> Next(acc, [])
    }
  }
  unfold(list, handler)
}

pub fn fold_chunks(
  over stream: Stream(element),
  from initial: acc,
  with f: fn(acc, List(element)) -> Consume(acc),
  max max_demand: Int,
) -> Result(acc, Dynamic) {
  use source <- result.try(to_producer(stream))
  use #(sink, ack) <- result.map(to_consumer(initial, f))
  source.subscribe(source, sink.subject, max_demand)
  process.receive_forever(ack)
}

pub fn to_list(stream: Stream(element)) -> Result(List(element), Dynamic) {
  let handler = fn(acc, elements) { Consume(list.append(acc, elements)) }
  fold_chunks(stream, [], handler, default_max_demand)
}

pub fn take(from stream: Stream(element), up_to desired: Int) -> Stream(element) {
  todo
}

pub fn drop(from stream: Stream(element), up_to desired: Int) -> Stream(element) {
  todo
}

pub fn map(over stream: Stream(a), with f: fn(a) -> b) -> Stream(b) {
  todo
}

pub fn append(to first: Stream(a), suffix second: Stream(a)) -> Stream(a) {
  todo
}

pub fn flatten(stream: Stream(Stream(element))) -> Stream(element) {
  todo
}

pub fn concat(streams: List(Stream(element))) -> Stream(element) {
  flatten(from_list(streams))
}

pub fn flat_map(over stream: Stream(a), with f: fn(a) -> Stream(b)) -> Stream(b) {
  stream
  |> map(f)
  |> flatten
}

pub fn filter(stream: Stream(a), keeping predicate: fn(a) -> Bool) -> Stream(a) {
  todo
}

pub fn filter_map(
  stream: Stream(a),
  keeping_with f: fn(a) -> Result(b, c),
) -> Stream(b) {
  todo
}

pub fn cycle(stream: Stream(element)) -> Stream(element) {
  repeat(stream)
  |> flatten
}

pub fn range(from start: Int, to stop: Int) -> Stream(Int) {
  todo
}

pub fn iterate(
  from initial: element,
  with f: fn(element) -> element,
) -> Stream(element) {
  todo
}

pub fn take_while(
  in stream: Stream(element),
  satisfying predicate: fn(element) -> Bool,
) -> Stream(element) {
  todo
}

pub fn drop_while(
  in stream: Stream(element),
  satisfying predicate: fn(element) -> Bool,
) -> Stream(element) {
  todo
}

pub fn scan(
  over stream: Stream(element),
  from initial: acc,
  with f: fn(acc, element) -> acc,
) -> Stream(acc) {
  todo
}

pub fn zip(left: Stream(a), right: Stream(b)) -> Stream(#(a, b)) {
  todo
}

pub fn intersperse(
  over stream: Stream(element),
  with elem: element,
) -> Stream(element) {
  todo
}

pub fn empty() -> Stream(element) {
  todo
}

pub fn once(f: fn() -> element) -> Stream(element) {
  todo
}

pub fn single(elem: element) -> Stream(element) {
  once(fn() { elem })
}

pub fn interleave(
  left: Stream(element),
  with right: Stream(element),
) -> Stream(element) {
  todo
}

fn to_producer(stream: Stream(element)) -> Result(Source(element), Dynamic) {
  let handle_demand = fn(continuation, demand) {
    case continuation(demand) {
      Continue(events, accumulator) -> {
        source.Next(events, accumulator)
      }
      Stop -> {
        source.Done
      }
    }
  }
  source.new(stream.continuation, handle_demand)
}

fn to_consumer(
  initial: acc,
  f: fn(acc, List(element)) -> Consume(acc),
) -> Result(#(Sink(element), process.Subject(acc)), Dynamic) {
  let handle_events = fn(state, events) {
    case f(state, events) {
      Consume(state) -> actor.continue(state)
      Complete -> actor.Stop(process.Normal)
    }
  }
  let ack = process.new_subject()
  sink.new_with_shutdown(initial, handle_events, fn(state) {
    process.send(ack, state)
  })
  |> result.map(fn(sink) { #(sink, ack) })
}
