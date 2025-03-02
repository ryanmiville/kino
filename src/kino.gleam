import gleam/erlang/process
import gleam/io
import gleam/list
import gleam/otp/actor
import gleam/string
import kino/consumer
import kino/gen_stage
import kino/producer
import kino/producer_consumer
import logging

pub fn main() {
  logging.configure()
  logging.set_level(logging.Debug)
  let assert Ok(producer) = producer()
  let assert Ok(producer_consumer) = producer_consumer()
  let assert Ok(consumer) = consumer()

  consumer.subject
  |> gen_stage.subscribe(producer_consumer.producer_subject, 9)

  producer_consumer.consumer_subject
  |> gen_stage.subscribe(producer.subject, 13)

  process.sleep(5000)
}

fn producer() {
  producer.new(0, fn(state, demand) {
    let events = list.range(state, state + demand - 1)
    gen_stage.Next(events, state + demand)
  })
}

fn producer_consumer() {
  producer_consumer.new(0, fn(state, events) {
    logging.log(
      logging.Debug,
      "ProducerConsumer: Received events: " <> string.inspect(events),
    )
    // let events = list.map(events, fn(x) { x * 2 })
    gen_stage.Next(events, state)
  })
}

fn consumer() {
  consumer.new(0, fn(state, events) {
    io.debug(events)
    process.sleep(500)
    actor.continue(state)
  })
}
