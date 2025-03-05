import gleam/option.{type Option, None, Some}
import kino/stage/consumer.{type Consumer}
import kino/stage/internal/stage
import kino/stage/producer.{type Producer}
import kino/stage/producer_consumer.{type ProducerConsumer}

pub opaque type Builder(event) {
  Builder(consumer: Consumer(event), min_demand: Option(Int), max_demand: Int)
}

pub fn consumer(consumer: Consumer(event)) -> Builder(event) {
  Builder(consumer:, min_demand: None, max_demand: 1000)
}

pub fn max_demand(builder: Builder(event), max_demand: Int) {
  Builder(..builder, max_demand:)
}

pub fn min_demand(builder: Builder(event), min_demand: Int) {
  Builder(..builder, min_demand: Some(min_demand))
}

pub fn to(builder: Builder(event), producer: Producer(event)) {
  let Builder(consumer:, min_demand:, max_demand:) = builder
  let min_demand = option.unwrap(min_demand, max_demand / 2)
  stage.subscribe(consumer, producer, min_demand, max_demand)
}

pub fn through(
  builder: Builder(event),
  pc: ProducerConsumer(a, event),
) -> Builder(a) {
  to(builder, producer_consumer.as_producer(pc))
  consumer(producer_consumer.as_consumer(pc))
}
