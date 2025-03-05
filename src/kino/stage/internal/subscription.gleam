import gleam/erlang/process.{type Subject}
import gleam/option.{type Option, None, Some}
import kino/stage.{type ConsumerMessage, type ProducerMessage}

pub opaque type Subscription(event) {
  Subscription(
    to: Subject(ProducerMessage(event)),
    min_demand: Option(Int),
    max_demand: Int,
  )
}

pub fn to(producer: Subject(ProducerMessage(event))) {
  Subscription(producer, None, 1000)
}

pub fn min_demand(builder: Subscription(event), min_demand: Int) {
  Subscription(..builder, min_demand: Some(min_demand))
}

pub fn max_demand(builder: Subscription(event), max_demand: Int) {
  Subscription(..builder, max_demand:)
}

pub fn subscribe(
  consumer consumer: Subject(ConsumerMessage(event)),
  to subscription: Subscription(event),
) {
  let Subscription(to:, min_demand:, max_demand:) = subscription
  let min_demand = option.unwrap(min_demand, max_demand / 2)
  process.send(consumer, stage.ConsumerSubscribe(to, min_demand, max_demand))
}
