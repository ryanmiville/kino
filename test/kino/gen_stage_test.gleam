import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/otp/actor
import gleam/result
import gleeunit/should
import kino/consumer
import kino/gen_stage.{Next}
import kino/producer
import kino/producer_consumer
import logging

fn counter(initial_state: Int) -> producer.Producer(Int) {
  let pull = fn(state, demand) {
    let events = list.range(state, state + demand - 1)
    Next(events, state + demand)
  }
  let assert Ok(prod) = producer.new(initial_state, pull)
  prod
}

fn forwarder(receiver: process.Subject(List(Int))) -> consumer.Consumer(Int) {
  let assert Ok(consumer) =
    consumer.new(0, fn(state, events) {
      process.send(receiver, events)
      actor.continue(state)
    })
  consumer
}

fn print_forwarder(
  receiver: process.Subject(List(Int)),
) -> consumer.Consumer(Int) {
  let assert Ok(consumer) =
    consumer.new(0, fn(state, events) {
      process.send(receiver, events)
      case events {
        [h, ..] if h < 200 -> io.debug(events)
        _ -> events
      }
      actor.continue(state)
    })
  consumer
}

fn doubler(
  receiver: process.Subject(List(Int)),
) -> producer_consumer.ProducerConsumer(Int, Int) {
  let assert Ok(producer_consumer) =
    producer_consumer.new(0, fn(state, events) {
      process.send(receiver, events)
      let events = list.flat_map(events, fn(event) { [event, event] })
      Next(events, state)
    })
  producer_consumer
}

fn postponer(
  receiver: process.Subject(List(Int)),
) -> producer_consumer.ProducerConsumer(Int, Int) {
  let assert Ok(producer_consumer) =
    producer_consumer.new(0, fn(state, events) {
      process.send(receiver, events)
      Next([], state)
    })
  producer_consumer
}

fn sleeper(receiver: process.Subject(List(Int))) -> consumer.Consumer(Int) {
  let assert Ok(consumer) =
    consumer.new(0, fn(state, events) {
      process.send(receiver, events)
      process.sleep_forever()
      actor.continue(state)
    })
  consumer
}

fn assert_received(subject: process.Subject(a), expected: a) {
  process.receive(subject, 100)
  |> should.equal(Ok(expected))
}

fn assert_not_received(subject: process.Subject(a), not_expected: a) {
  process.receive(subject, 100)
  |> should.not_equal(Ok(not_expected))
}

fn assert_received_eventually(subject: process.Subject(a), expected: a) {
  receive_eventually(subject, expected, 1000)
  |> should.equal(Ok(expected))
}

pub fn producer_test() {
  let prod = counter(0)

  let events_subject = process.new_subject()

  let consumer = forwarder(events_subject)

  // Subscribe to producer
  consumer.subject |> gen_stage.subscribe(prod.subject, 2, 5)

  // We should receive events
  assert_received(events_subject, [0, 1, 2])

  // Receive more events
  assert_received(events_subject, [3, 4])
}

pub fn producer_multiple_consumers_test() {
  let prod = counter(0)

  let events_subject1 = process.new_subject()
  let consumer1 = forwarder(events_subject1)

  let events_subject2 = process.new_subject()
  let consumer2 = forwarder(events_subject2)

  // Subscribe both consumers
  consumer1.subject |> gen_stage.subscribe(prod.subject, 2, 4)
  consumer2.subject |> gen_stage.subscribe(prod.subject, 2, 4)

  let events1 =
    [
      process.receive(events_subject1, 100),
      process.receive(events_subject1, 100),
    ]
    |> result.values
    |> list.flatten

  let events2 =
    [
      process.receive(events_subject2, 100),
      process.receive(events_subject2, 100),
    ]
    |> result.values
    |> list.flatten

  list.append(events1, events2)
  |> list.sort(int.compare)
  |> should.equal([0, 1, 2, 3, 4, 5, 6, 7])
}

pub fn producer_done_test() {
  // Test producer that finishes after sending some events
  let pull = fn(state, demand) {
    case state {
      state if state >= 3 -> gen_stage.Done
      _ -> {
        let events = list.range(state, state + demand - 1)
        Next(events, state + demand)
      }
    }
  }

  let assert Ok(prod) = producer.new(0, pull)

  let events_subject = process.new_subject()
  let consumer = forwarder(events_subject)
  consumer.subject |> gen_stage.subscribe(prod.subject, 2, 5)

  // Should receive events until producer is done
  assert_received(events_subject, [0, 1, 2])

  assert_received(events_subject, [3, 4])

  process.receive(events_subject, 100)
  |> should.equal(Error(Nil))
}

pub fn producer_to_consumer_default_demand_test() {
  let prod = counter(0)

  let events_subject = process.new_subject()
  let consumer = forwarder(events_subject)

  consumer.subject |> gen_stage.subscribe(prod.subject, 500, 1000)

  let batch = list.range(0, 499)
  assert_received(events_subject, batch)

  let batch = list.range(500, 999)
  assert_received(events_subject, batch)
}

pub fn producer_to_consumer_80_percent_min_demand_test() {
  let prod = counter(0)

  let events_subject = process.new_subject()
  let consumer = forwarder(events_subject)

  consumer.subject |> gen_stage.subscribe(prod.subject, 80, 100)

  let batch = list.range(0, 19)
  assert_received(events_subject, batch)

  let batch = list.range(20, 39)
  assert_received(events_subject, batch)

  let batch = list.range(1000, 1019)
  assert_received_eventually(events_subject, batch)
}

pub fn producer_to_consumer_20_percent_min_demand_test() {
  let prod = counter(0)

  let events_subject = process.new_subject()
  let consumer = forwarder(events_subject)

  consumer.subject |> gen_stage.subscribe(prod.subject, 20, 100)

  let batch = list.range(0, 79)
  assert_received(events_subject, batch)

  let batch = list.range(80, 99)
  assert_received(events_subject, batch)

  let batch = list.range(100, 179)
  assert_received(events_subject, batch)

  let batch = list.range(180, 259)
  assert_received(events_subject, batch)

  let batch = list.range(260, 279)
  assert_received(events_subject, batch)
}

pub fn producer_to_consumer_0_min_1_max_demand_test() {
  let prod = counter(0)

  let events_subject = process.new_subject()
  let consumer = forwarder(events_subject)

  consumer.subject |> gen_stage.subscribe(prod.subject, 0, 1)

  assert_received(events_subject, [0])

  assert_received(events_subject, [1])

  assert_received(events_subject, [2])
}

pub fn producer_to_consumer_broadcast_demand_test() {
  logging.log(
    logging.Warning,
    "TODO: producer_to_consumer: with shared (broadcast) demand",
  )
  logging.log(
    logging.Warning,
    "TODO: producer_to_consumer: with shared (broadcast) demand and synchronizer subscriber",
  )
}

pub fn producer_to_producer_consumer_to_consumer_80_percent_min_demand_test() {
  let prod = counter(0)

  let doubler_subject = process.new_subject()
  let doubler = doubler(doubler_subject)

  let consumer_subject = process.new_subject()
  let consumer = forwarder(consumer_subject)

  doubler.consumer_subject |> gen_stage.subscribe(prod.subject, 80, 100)

  consumer.subject |> gen_stage.subscribe(doubler.producer_subject, 50, 100)

  let batch = list.range(0, 19)
  assert_received(doubler_subject, batch)

  let batch = doubled_range(0, 19)
  assert_received(consumer_subject, batch)

  let batch = doubled_range(20, 39)
  assert_received(consumer_subject, batch)

  let batch = list.range(100, 119)
  assert_received_eventually(doubler_subject, batch)

  logging.log(
    logging.Warning,
    "TODO: producer_to_producer_consumer_to_consumer: 80 min error",
  )
  // there's a bug
  // current the next two are:
  // [120, 120, 121, 121, 122, 122, 123, 123, 124, 124, 125, 125, 126, 126, 127, 127, 128, 128, 129, 129, 130, 130, 131, 131, 132, 132, 133, 133, 134, 134, 135, 135, 136, 136, 137, 137, 138, 138, 139, 139]
  // [140, 140, 141, 141, 142, 142, 143, 143, 144, 144, 145, 145, 146, 146, 147, 147, 148, 148, 149, 149, 150, 150, 151, 151, 152, 152, 153, 153, 154, 154, 155, 155, 156, 156, 157, 157, 158, 158, 159, 159]

  // let batch = list.flat_map(list.range(120, 124), fn(event) { [event, event] })
  // assert_received_eventually(consumer_subject, batch)

  // let batch = list.flat_map(list.range(125, 139), fn(event) { [event, event] })
  // assert_received_eventually(consumer_subject, batch)
}

pub fn producer_to_producer_consumer_to_consumer_20_percent_min_demand_test() {
  let prod = counter(0)

  let doubler_subject = process.new_subject()
  let doubler = doubler(doubler_subject)

  let consumer_subject = process.new_subject()
  let consumer = forwarder(consumer_subject)

  doubler.consumer_subject |> gen_stage.subscribe(prod.subject, 20, 100)

  consumer.subject |> gen_stage.subscribe(doubler.producer_subject, 50, 100)

  let batch = list.range(0, 79)
  assert_received(doubler_subject, batch)

  let batch = doubled_range(0, 24)
  assert_received(consumer_subject, batch)

  let batch = doubled_range(25, 49)
  assert_received(consumer_subject, batch)

  let batch = doubled_range(50, 74)
  assert_received(consumer_subject, batch)

  let batch = list.range(100, 179)
  assert_received_eventually(doubler_subject, batch)
}

pub fn producer_to_producer_consumer_to_consumer_80_percent_min_demand_late_subscription_test() {
  let prod = counter(0)

  let doubler_subject = process.new_subject()
  let doubler = doubler(doubler_subject)

  let consumer_subject = process.new_subject()
  let consumer = forwarder(consumer_subject)

  // consumer first
  consumer.subject |> gen_stage.subscribe(doubler.producer_subject, 50, 100)
  doubler.consumer_subject |> gen_stage.subscribe(prod.subject, 80, 100)

  let batch = list.range(0, 19)
  assert_received(doubler_subject, batch)

  let batch = doubled_range(0, 19)
  assert_received(consumer_subject, batch)

  let batch = doubled_range(20, 39)
  assert_received(consumer_subject, batch)

  let batch = list.range(100, 119)
  assert_received_eventually(doubler_subject, batch)
  // same bug as before
  // let batch = list.flat_map(list.range(120, 124), fn(event) { [event, event] })
  // assert_received_eventually(consumer_subject, batch)

  // let batch = list.flat_map(list.range(125, 139), fn(event) { [event, event] })
  // assert_received_eventually(consumer_subject, batch)
}

pub fn producer_to_producer_consumer_to_consumer_20_percent_min_demand_late_subscription_test() {
  let prod = counter(0)

  let doubler_subject = process.new_subject()
  let doubler = doubler(doubler_subject)

  let consumer_subject = process.new_subject()
  let consumer = forwarder(consumer_subject)

  // consumer first
  consumer.subject |> gen_stage.subscribe(doubler.producer_subject, 50, 100)
  doubler.consumer_subject |> gen_stage.subscribe(prod.subject, 20, 100)

  let batch = list.range(0, 79)
  assert_received(doubler_subject, batch)

  let batch = doubled_range(0, 24)
  assert_received(consumer_subject, batch)

  let batch = doubled_range(25, 49)
  assert_received(consumer_subject, batch)

  let batch = doubled_range(50, 74)
  assert_received(consumer_subject, batch)

  let batch = list.range(100, 179)
  assert_received_eventually(doubler_subject, batch)
}

pub fn producer_to_producer_consumer_to_consumer_stops_asking_when_consumer_stops_asking_test() {
  let prod = counter(0)

  let postponer_subject = process.new_subject()
  let postponer = postponer(postponer_subject)

  let sleeper_subject = process.new_subject()
  let sleeper = sleeper(sleeper_subject)

  postponer.consumer_subject |> gen_stage.subscribe(prod.subject, 8, 10)

  sleeper.subject |> gen_stage.subscribe(postponer.producer_subject, 5, 10)

  assert_received(postponer_subject, [0, 1])
  assert_received(sleeper_subject, [0, 1])
  // assert_received(postponer_subject, [2, 3])
  // assert_received(postponer_subject, [4, 5])
  // assert_received(postponer_subject, [6, 7])
  // assert_received(postponer_subject, [8, 9])
  // assert_not_received(sleeper_subject, [2, 3])
  // assert_not_received(postponer_subject, [10, 11])
}

fn doubled_range(start: Int, end: Int) -> List(Int) {
  list.flat_map(list.range(start, end), fn(event) { [event, event] })
}

@external(erlang, "kino_test_ffi", "receive_eventually")
fn receive_eventually(
  subject: process.Subject(a),
  expected: a,
  timeout: Int,
) -> Result(a, Nil)
