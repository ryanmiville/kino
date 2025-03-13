import gleam/option.{type Option, None, Some}
import kino/gen_stage/consumer.{type Consumer}
import kino/gen_stage/internal/stage
import kino/gen_stage/processor.{type Processor}
import kino/gen_stage/producer.{type Producer}

pub opaque type Subscription(event) {
  Subscription(
    consumer: Consumer(event),
    min_demand: Option(Int),
    max_demand: Int,
  )
}

pub fn from(consumer: Consumer(event)) -> Subscription(event) {
  Subscription(consumer:, min_demand: None, max_demand: 1000)
}

pub fn with_max_demand(
  builder: Subscription(event),
  max_demand: Int,
) -> Subscription(event) {
  Subscription(..builder, max_demand:)
}

pub fn with_min_demand(
  builder: Subscription(event),
  min_demand: Int,
) -> Subscription(event) {
  Subscription(..builder, min_demand: Some(min_demand))
}

pub fn through(
  builder: Subscription(event),
  pc: Processor(a, event),
) -> Subscription(a) {
  to(builder, processor.as_producer(pc))
  from(processor.as_consumer(pc))
}

pub fn to(builder: Subscription(event), producer: Producer(event)) -> Nil {
  let Subscription(consumer:, min_demand:, max_demand:) = builder
  let min_demand = option.unwrap(min_demand, max_demand / 2)
  stage.subscribe(consumer, producer, min_demand, max_demand)
}
