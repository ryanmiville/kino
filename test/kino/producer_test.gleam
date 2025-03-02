import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/string
import gleeunit/should
import kino/consumer
import kino/gen_stage.{Next}
import kino/producer
import logging

pub fn producer_test() {
  //   // Test setup - create a simple counter producer
  let initial_state = 0
  let pull = fn(state, demand) {
    let events = list.range(state, state + demand - 1)
    Next(events, state + demand)
  }

  // Create producer
  let assert Ok(prod) = producer.new(initial_state, pull)

  // Create a test consumer
  let events_subject = process.new_subject()

  let assert Ok(consumer) =
    consumer.new(0, fn(state, events) {
      process.send(events_subject, events)
      actor.continue(state)
    })

  // Subscribe to producer
  consumer.subject |> gen_stage.subscribe(prod.subject, 5)

  // We should receive events
  let assert Ok(events) = process.receive(events_subject, 100)
  events
  |> should.equal([0, 1, 2])

  // Receive more events
  let assert Ok(events) = process.receive(events_subject, 100)
  events
  |> should.equal([3, 4])
}

pub fn producer_multiple_consumers_test() {
  let initial_state = 0
  let pull = fn(state, demand) {
    let events = list.range(state, state + demand - 1)
    Next(events, state + demand)
  }

  let assert Ok(prod) = producer.new(initial_state, pull)

  let events_subject1 = process.new_subject()
  let assert Ok(consumer1) =
    consumer.new(0, fn(state, events) {
      logging.log(
        logging.Debug,
        "consumer1 received events: " <> string.inspect(events),
      )
      process.send(events_subject1, events)
      process.sleep(50)
      actor.continue(state)
    })
  let events_subject2 = process.new_subject()
  let assert Ok(consumer2) =
    consumer.new(0, fn(state, events) {
      logging.log(
        logging.Debug,
        "consumer2 received events: " <> string.inspect(events),
      )
      process.send(events_subject2, events)
      process.sleep(50)
      actor.continue(state)
    })

  // Subscribe both consumers
  consumer1.subject |> gen_stage.subscribe(prod.subject, 4)
  consumer2.subject |> gen_stage.subscribe(prod.subject, 4)

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
  let assert Ok(consumer) =
    consumer.new(0, fn(state, events) {
      process.send(events_subject, events)
      actor.continue(state)
    })

  consumer.subject |> gen_stage.subscribe(prod.subject, 5)

  // Should receive events until producer is done
  process.receive(events_subject, 100)
  |> should.equal(Ok([0, 1, 2]))

  process.receive(events_subject, 100)
  |> should.equal(Ok([3, 4]))

  process.receive(events_subject, 100)
  |> should.equal(Error(Nil))
}
