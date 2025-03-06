import gleam/erlang/process
import gleam/list
import gleam/otp/actor.{type StartError}
import gleam/result
import kino/consumer
import logging

// import kino/processor
import kino/producer.{type Produce, type Producer, Done, Next}
import kino/subscription

pub type Stream(a) {
  Stream(producer: fn() -> Result(Producer(a), StartError))
}

pub fn from_list(chunk: List(a)) -> Stream(a) {
  use <- Stream
  producer.new(True)
  |> producer.pull(fn(continue, _) {
    case continue {
      True -> Next(chunk, False)
      False -> Done
    }
  })
  |> producer.start()
}

pub fn single(value: a) -> Stream(a) {
  from_list([value])
}

pub fn unfold(initial: state, f: fn(state) -> Produce(state, a)) -> Stream(a) {
  use <- Stream
  producer.new(initial)
  |> producer.pull(fn(state, _) { f(state) })
  |> producer.start()
}

pub fn fold_chunks(
  stream: Stream(a),
  initial: acc,
  f: fn(acc, List(a)) -> acc,
) -> Result(acc, StartError) {
  use producer <- result.try(stream.producer())
  let ack = process.new_subject()
  let consumer =
    consumer.new(initial)
    |> consumer.handle_events(fn(acc, events) { actor.continue(f(acc, events)) })
    |> consumer.on_shutdown(fn(acc) { process.send(ack, acc) })
    |> consumer.start
  use consumer <- result.map(consumer)
  subscription.from(consumer) |> subscription.to(producer)
  process.receive_forever(ack)
}

pub fn to_list(stream: Stream(a)) -> Result(List(a), StartError) {
  to_chunks(stream)
  |> result.map(list.flatten)
}

pub fn to_chunks(stream: Stream(a)) -> Result(List(List(a)), StartError) {
  let f = fn(acc, chunk) -> List(List(a)) { [chunk, ..acc] }
  fold_chunks(stream, [], f) |> result.map(list.reverse)
}

pub fn main() {
  logging.configure()
  logging.set_level(logging.Debug)
  let assert Ok([1]) = single(1) |> to_list
  let assert Ok([1, 2, 3]) = from_list([1, 2, 3]) |> to_list
}
