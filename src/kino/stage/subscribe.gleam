import kino/stage
import kino/stage/consumer.{type Consumer}
import kino/stage/producer.{type Producer}
import kino/stage/producer_consumer.{type ProducerConsumer}

pub type Nothing

pub opaque type Flow(in, out) {
  Source(producer: Producer(out))
  Flow(consumer: Consumer(in), producer: Producer(out))
  Sink(consumer: Consumer(in))
}

pub type Complete =
  Flow(Nothing, Nothing)

pub type Source(out) =
  Flow(Nothing, out)

pub type Sink(in) =
  Flow(in, Nothing)

// Sink(consumer: Consumer(in), subscribe: fn(Producer(in)) -> Nil)
// Source(producer: Producer(out), subscribe: fn(Consumer(out)) -> Nil)
// Sink(consumer: Consumer(in))
// Flow(sub: fn(ProducerConsumer(in, out)) -> Nil)
// Flow(producer_consumer: ProducerConsumer(in, out))
// Source(sub: fn(Producer(out)) -> Nil)
// Source(producer: Producer(out))
// Through(
//   downstream: Flow(Hidden, out),
//   upstream: Flow(in, Hidden),
// )

pub fn source(producer: Producer(out)) -> Source(out) {
  Source(producer)
}

pub fn sink(consumer: Consumer(in)) -> Sink(in) {
  Sink(consumer)
}

// pub fn consumer(consumer: Consumer(in)) -> Flow(in, Nothing) {
//   Sink(consumer, fn(producer: Producer(in)) {
//     stage.subscribe(consumer, producer)
//   })
// }

pub fn flow(producer_consumer: ProducerConsumer(in, out)) -> Flow(in, out) {
  Flow(producer_consumer.consumer_subject, producer_consumer.producer_subject)
  // Sink(producer_consumer.consumer_subject, fn(producer: Producer(in)) {
  //   stage.subscribe(producer_consumer.consumer_subject, producer)
  // })
}

pub fn through(
  downstream: Flow(in, out),
  producer_consumer: ProducerConsumer(new_in, in),
) -> Flow(new_in, out) {
  case downstream {
    Sink(consumer) -> todo
    Flow(consumer, producer) -> todo
    Source(_) -> panic as "unreachable"
  }
  // let down = hide_in(downstream)
  // let up = hide_out(flow(producer_consumer))
  // Through(down, up)
}

fn do_something
pub fn through_flow(
  downstream: Flow(in, out),
  flow: Flow(new_in, in),
) -> Flow(new_in, out) {
  todo
  // let down = hide_in(downstream)
  // let up = hide_out(flow(producer_consumer))
  // Through(down, up)
}

pub fn to(downstream: Flow(in, out), producer: Producer(in)) -> Source(out) {
  todo
  // let down = hide_in(downstream)
  // let up = source(producer) |> hide_out
  // Through(down, up)
}

pub fn to_source(downstream: Flow(in, out), source: Source(in)) -> Source(out) {
  todo
  // let down = hide_in(downstream)
  // let up = source(producer) |> hide_out
  // Through(down, up)
}

// pub fn subscribe(subscription: Flow(Nothing, Nothing)) -> Nil {
//   todo
//   // let assert Through(downstream, Source(producer)) = subscription
//   // do_subscribe(downstream, producer)
// }

fn do_subscribe(sub: Flow(in, out), producer: Producer(in)) {
  todo
  // case sub {
  //   Sink(consumer) -> todo
  //   Flow(pc) -> todo
  //   Source(producer) -> todo
  //   Through(down, up) -> todo
  // }
}

fn subscribe(consumer: Consumer(a), producer: Producer(a)) -> Nil {
  stage.subscribe(consumer, producer, 500, 1000)
}
