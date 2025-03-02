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

fn assert_received(subject: process.Subject(a), expected: a) {
  process.receive(subject, 100)
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
    |> io.debug
    |> list.flatten

  let events2 =
    [
      process.receive(events_subject2, 100),
      process.receive(events_subject2, 100),
    ]
    |> result.values
    |> io.debug
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
