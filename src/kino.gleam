import gleam/erlang/process
import gleam/io
import gleam/list
import gleam/otp/actor
import kino/consumer
import kino/gen_stage
import kino/producer
import logging

pub fn main() {
  logging.configure()
  logging.set_level(logging.Debug)
  let assert Ok(producer) = producer()
  let assert Ok(consumer) = consumer()
  gen_stage.subscribe(producer.subject, consumer.subject, 10)
  process.sleep(5000)
}

fn producer() {
  producer.new(0, fn(state, demand) {
    let events = list.range(state, state + demand - 1)
    gen_stage.Next(events, state + demand)
  })
}

fn consumer() {
  consumer.new(0, fn(state, events) {
    io.debug(events)
    process.sleep(500)
    actor.continue(state)
  })
}
