import gleam/erlang/process
import gleam/list
import gleam/otp/actor
import gleeunit
import gleeunit/should
import kino/consumer
import kino/processor.{type Processor}
import kino/producer
import kino/subscription
import logging

pub fn main() {
  logging.configure()
  logging.set_level(logging.Error)
  gleeunit.main()
}

fn counter(initial_state: Int) -> producer.Producer(Int) {
  let pull = fn(state, demand) {
    let events = list.range(state, state + demand - 1)
    producer.Next(events, state + demand)
  }
  let assert Ok(prod) =
    producer.new(initial_state)
    |> producer.pull(pull)
    |> producer.start
  prod
}

fn forwarder(receiver: process.Subject(List(Int))) -> consumer.Consumer(Int) {
  let assert Ok(consumer) =
    consumer.new(0)
    |> consumer.handle_events(fn(state, events) {
      process.send(receiver, events)
      actor.continue(state)
    })
    |> consumer.start
  consumer
}

fn doubler(receiver: process.Subject(List(Int))) -> Processor(Int, Int) {
  let assert Ok(processor) =
    processor.new(0)
    |> processor.handle_events(fn(state, events) {
      process.send(receiver, events)
      let events = list.flat_map(events, fn(event) { [event, event] })
      processor.Next(events, state)
    })
    |> processor.start
  processor
}

fn pass_through(receiver: process.Subject(List(Int))) -> Processor(Int, Int) {
  let assert Ok(processor) =
    processor.new(0)
    |> processor.handle_events(fn(state, events) {
      process.send(receiver, events)
      processor.Next(events, state)
    })
    |> processor.start
  processor
}

fn discarder(receiver: process.Subject(List(Int))) -> Processor(Int, Int) {
  let assert Ok(processor) =
    processor.new(0)
    |> processor.handle_events(fn(state, events) {
      process.send(receiver, events)
      processor.Next([], state)
    })
    |> processor.start
  processor
}

fn sleeper(receiver: process.Subject(List(Int))) -> consumer.Consumer(Int) {
  let assert Ok(consumer) =
    consumer.new(0)
    |> consumer.handle_events(fn(state, events) {
      process.send(receiver, events)
      process.sleep_forever()
      actor.continue(state)
    })
    |> consumer.start
  consumer
}

fn assert_received(subject: process.Subject(a), expected: a, timeout: Int) {
  process.receive(subject, timeout)
  |> should.equal(Ok(expected))
}

fn assert_not_received(
  subject: process.Subject(a),
  not_expected: a,
  timeout: Int,
) {
  process.receive(subject, timeout)
  |> should.not_equal(Ok(not_expected))
}

fn assert_received_eventually(
  subject: process.Subject(a),
  expected: a,
  timeout: Int,
) {
  receive_eventually(subject, expected, timeout)
  |> should.equal(Ok(expected))
}

pub fn producer_to_consumer_default_demand_test() {
  let prod = counter(0)

  let events_subject = process.new_subject()
  let consumer = forwarder(events_subject)

  subscription.from(consumer)
  |> subscription.with_min_demand(500)
  |> subscription.with_max_demand(1000)
  |> subscription.to(prod)

  let batch = list.range(0, 499)
  assert_received(events_subject, batch, 20)

  let batch = list.range(500, 999)
  assert_received(events_subject, batch, 20)
}

pub fn producer_to_consumer_80_percent_min_demand_test() {
  let prod = counter(0)

  let events_subject = process.new_subject()
  let consumer = forwarder(events_subject)

  subscription.from(consumer)
  |> subscription.with_min_demand(80)
  |> subscription.with_max_demand(100)
  |> subscription.to(prod)

  let batch = list.range(0, 19)
  assert_received(events_subject, batch, 20)

  let batch = list.range(20, 39)
  assert_received(events_subject, batch, 20)

  let batch = list.range(1000, 1019)
  assert_received_eventually(events_subject, batch, 20)
}

pub fn producer_to_consumer_20_percent_min_demand_test() {
  let prod = counter(0)

  let events_subject = process.new_subject()
  let consumer = forwarder(events_subject)

  subscription.from(consumer)
  |> subscription.with_min_demand(20)
  |> subscription.with_max_demand(100)
  |> subscription.to(prod)

  let batch = list.range(0, 79)
  assert_received(events_subject, batch, 20)

  let batch = list.range(80, 99)
  assert_received(events_subject, batch, 20)

  let batch = list.range(100, 179)
  assert_received(events_subject, batch, 20)

  let batch = list.range(180, 259)
  assert_received(events_subject, batch, 20)

  let batch = list.range(260, 279)
  assert_received(events_subject, batch, 20)
}

pub fn producer_to_consumer_0_min_1_max_demand_test() {
  let prod = counter(0)

  let events_subject = process.new_subject()
  let consumer = forwarder(events_subject)

  subscription.from(consumer)
  |> subscription.with_min_demand(0)
  |> subscription.with_max_demand(1)
  |> subscription.to(prod)

  assert_received(events_subject, [0], 20)

  assert_received(events_subject, [1], 20)

  assert_received(events_subject, [2], 20)
}

// pub fn producer_to_consumer_broadcast_demand_test() {
//   logging.log(
//     logging.Warning,
//     "TODO: producer_to_consumer: with shared (broadcast) demand",
//   )
//   logging.log(
//     logging.Warning,
//     "TODO: producer_to_consumer: with shared (broadcast) demand and synchronizer subscriber",
//   )
// }

pub fn producer_to_processor_to_consumer_80_percent_min_demand_test() {
  let prod = counter(0)

  let doubler_subject = process.new_subject()
  let doubler = doubler(doubler_subject)

  let consumer_subject = process.new_subject()
  let consumer = forwarder(consumer_subject)

  processor.as_consumer(doubler)
  |> subscription.from
  |> subscription.with_min_demand(80)
  |> subscription.with_max_demand(100)
  |> subscription.to(prod)

  subscription.from(consumer)
  |> subscription.with_min_demand(50)
  |> subscription.with_max_demand(100)
  |> subscription.through(doubler)

  let batch = list.range(0, 19)
  assert_received(doubler_subject, batch, 20)

  let batch = doubled_range(0, 19)
  assert_received(consumer_subject, batch, 20)

  let batch = doubled_range(20, 39)
  assert_received(consumer_subject, batch, 20)

  let batch = list.range(100, 119)
  assert_received_eventually(doubler_subject, batch, 100)

  let batch = list.flat_map(list.range(120, 124), fn(event) { [event, event] })
  assert_received_eventually(consumer_subject, batch, 100)

  let batch = list.flat_map(list.range(125, 139), fn(event) { [event, event] })
  assert_received_eventually(consumer_subject, batch, 100)
}

pub fn producer_to_processor_to_consumer_20_percent_min_demand_test() {
  let prod = counter(0)

  let doubler_subject = process.new_subject()
  let doubler = doubler(doubler_subject)

  let consumer_subject = process.new_subject()
  let consumer = forwarder(consumer_subject)

  processor.as_consumer(doubler)
  |> subscription.from
  |> subscription.with_min_demand(20)
  |> subscription.with_max_demand(100)
  |> subscription.to(prod)

  subscription.from(consumer)
  |> subscription.with_min_demand(50)
  |> subscription.with_max_demand(100)
  |> subscription.through(doubler)

  let batch = list.range(0, 79)
  assert_received(doubler_subject, batch, 20)

  let batch = doubled_range(0, 24)
  assert_received(consumer_subject, batch, 20)

  let batch = doubled_range(25, 49)
  assert_received(consumer_subject, batch, 20)

  let batch = doubled_range(50, 74)
  assert_received(consumer_subject, batch, 20)

  let batch = list.range(100, 179)
  assert_received_eventually(doubler_subject, batch, 100)
}

pub fn producer_to_processor_to_consumer_80_percent_min_demand_late_subscription_test() {
  let prod = counter(0)

  let doubler_subject = process.new_subject()
  let doubler = doubler(doubler_subject)

  let consumer_subject = process.new_subject()
  let consumer = forwarder(consumer_subject)

  // consumer first
  subscription.from(consumer)
  |> subscription.with_min_demand(50)
  |> subscription.with_max_demand(100)
  |> subscription.through(doubler)
  |> subscription.with_min_demand(80)
  |> subscription.with_max_demand(100)
  |> subscription.to(prod)

  let batch = list.range(0, 19)
  assert_received(doubler_subject, batch, 20)

  let batch = doubled_range(0, 19)
  assert_received(consumer_subject, batch, 20)

  let batch = doubled_range(20, 39)
  assert_received(consumer_subject, batch, 20)

  let batch = list.range(100, 119)
  assert_received_eventually(doubler_subject, batch, 100)

  let batch = list.flat_map(list.range(120, 124), fn(event) { [event, event] })
  assert_received_eventually(consumer_subject, batch, 100)

  let batch = list.flat_map(list.range(125, 139), fn(event) { [event, event] })
  assert_received_eventually(consumer_subject, batch, 100)
}

pub fn producer_to_processor_to_consumer_20_percent_min_demand_late_subscription_test() {
  let prod = counter(0)

  let doubler_subject = process.new_subject()
  let doubler = doubler(doubler_subject)

  let consumer_subject = process.new_subject()
  let consumer = forwarder(consumer_subject)

  subscription.from(consumer)
  |> subscription.with_min_demand(50)
  |> subscription.with_max_demand(100)
  |> subscription.through(doubler)
  |> subscription.with_min_demand(20)
  |> subscription.with_max_demand(100)
  |> subscription.to(prod)

  let batch = list.range(0, 79)
  assert_received(doubler_subject, batch, 20)

  let batch = doubled_range(0, 24)
  assert_received(consumer_subject, batch, 20)

  let batch = doubled_range(25, 49)
  assert_received(consumer_subject, batch, 20)

  let batch = doubled_range(50, 74)
  assert_received(consumer_subject, batch, 20)

  let batch = list.range(100, 179)
  assert_received_eventually(doubler_subject, batch, 100)
}

pub fn producer_to_processor_to_consumer_stops_asking_when_consumer_stops_asking_test() {
  let prod = counter(0)

  let pass_through_subject = process.new_subject()
  let pass_through = pass_through(pass_through_subject)

  let sleeper_subject = process.new_subject()
  let sleeper = sleeper(sleeper_subject)

  subscription.from(sleeper)
  |> subscription.with_min_demand(5)
  |> subscription.with_max_demand(10)
  |> subscription.through(pass_through)
  |> subscription.with_min_demand(8)
  |> subscription.with_max_demand(10)
  |> subscription.to(prod)

  assert_received(pass_through_subject, [0, 1], 20)
  assert_received(sleeper_subject, [0, 1], 20)
  assert_received(pass_through_subject, [2, 3], 20)
  assert_received(pass_through_subject, [4, 5], 20)
  assert_received(pass_through_subject, [6, 7], 20)
  assert_received(pass_through_subject, [8, 9], 20)
  assert_not_received(sleeper_subject, [2, 3], 20)
  assert_not_received(pass_through_subject, [10, 11], 20)
}

pub fn producer_to_processor_to_consumer_keeps_emitting_even_when_discarded_test() {
  let prod = counter(0)

  let discarder_subject = process.new_subject()
  let discarder = discarder(discarder_subject)

  let forwarder_subject = process.new_subject()
  let forwarder = forwarder(forwarder_subject)

  subscription.from(forwarder)
  |> subscription.with_min_demand(50)
  |> subscription.with_max_demand(100)
  |> subscription.through(discarder)
  |> subscription.with_min_demand(80)
  |> subscription.with_max_demand(100)
  |> subscription.to(prod)

  assert_received(discarder_subject, list.range(0, 19), 20)
  assert_received_eventually(discarder_subject, list.range(100, 119), 100)
  assert_received_eventually(discarder_subject, list.range(1000, 1019), 100)
}

// pub fn producer_to_processor_to_consumer_with_broadcast_demand_test() {
//   logging.log(
//     logging.Warning,
//     "TODO: producer_to_processor_to_consumer: with broadcast demand",
//   )
//   logging.log(
//     logging.Warning,
//     "TODO: producer_to_processor_to_consumer: with broadcast demand and synchronizer subscriber",
//   )
// }

// pub fn producer_to_processor_to_consumer_queued_events_with_lost_producer_test() {
//   logging.log(
//     logging.Warning,
//     "TODO: producer_to_processor_to_consumer: queued events with lost producer",
//   )
// }

fn doubled_range(start: Int, end: Int) -> List(Int) {
  list.flat_map(list.range(start, end), fn(event) { [event, event] })
}

@external(erlang, "kino_test_ffi", "receive_eventually")
fn receive_eventually(
  subject: process.Subject(a),
  expected: a,
  timeout: Int,
) -> Result(a, Nil)
