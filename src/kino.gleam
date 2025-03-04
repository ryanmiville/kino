import gleam/erlang/process
import gleam/io
import gleam/list
import gleam/otp/actor
import gleam/string
import kino/stage
import kino/stage/consumer
import kino/stage/internal/stage.{subscribe} as internal
import kino/stage/producer
import kino/stage/producer_consumer
import logging

pub fn main() {
  logging.configure()
  logging.set_level(logging.Debug)
  let assert Ok(producer) = producer()
  let assert Ok(producer_consumer) = producer_consumer()
  let assert Ok(consumer) = consumer()

  consumer
  |> subscribe(producer_consumer.producer_subject, 4, 9)

  producer_consumer.consumer_subject
  |> subscribe(producer, 6, 13)

  process.sleep(5000)
}

fn producer() {
  producer.new(0)
  |> producer.pull(fn(state, demand) {
    let events = list.range(state, state + demand - 1)
    stage.Next(events, state + demand)
  })
  |> producer.start
}

fn producer_consumer() {
  producer_consumer.new(0)
  |> producer_consumer.handle_events(fn(state, events) {
    logging.log(
      logging.Debug,
      "ProducerConsumer: Received events: " <> string.inspect(events),
    )
    // let events = list.map(events, fn(x) { x * 2 })
    stage.Next(events, state)
  })
  |> producer_consumer.start
}

fn consumer() {
  consumer.new(0)
  |> consumer.handle_events(fn(state, events) {
    io.debug(events)
    process.sleep(500)
    actor.continue(state)
  })
  |> consumer.start
}
