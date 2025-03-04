import gleam/erlang/process
import gleam/list
import gleam/otp/actor
import gleeunit/should
import kino/stage.{Next}
import kino/stage/consumer.{type Consumer}
import kino/stage/producer.{type Producer}
import kino/stage/producer_consumer.{type ProducerConsumer}
import kino/stage/subscribe.{type Complete, type Flow, type Source}

fn producer() -> Producer(a) {
  let assert Ok(prod) = producer.new(0) |> producer.start
  prod
}

fn producer_consumer() -> ProducerConsumer(a, b) {
  let assert Ok(pc) = producer_consumer.new(0) |> producer_consumer.start
  pc
}

fn consumer() -> Consumer(b) {
  let assert Ok(con) = consumer.new(0) |> consumer.start
  con
}

fn stages() -> #(Producer(a), ProducerConsumer(a, b), Consumer(b)) {
  let prod: Producer(a) = producer()
  let pc: ProducerConsumer(a, b) = producer_consumer()
  let con: Consumer(b) = consumer()
  #(prod, pc, con)
}

pub fn bottom_up_test() {
  let #(prod, pc, con) = stages()
  let _: Complete =
    subscribe.sink(con) |> subscribe.through(pc) |> subscribe.to(prod)
}

pub fn flow_up_test() {
  let #(prod, pc, con) = stages()
  let source: Source(String) = subscribe.flow(pc) |> subscribe.to(prod)
  let _: Complete = subscribe.sink(con) |> subscribe.to_source(source)
}

pub fn flow_sink_source_test() {
  let #(prod, pc, con) = stages()
  let flow: Flow(Int, String) = subscribe.flow(pc)
  let _: Complete =
    subscribe.sink(con) |> subscribe.through_flow(flow) |> subscribe.to(prod)
}
