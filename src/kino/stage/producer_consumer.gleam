import gleam/bool
import gleam/deque.{type Deque}
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type ProcessMonitor, type Selector, type Subject}
import gleam/function
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/set.{type Set}
import gleam/string
import kino/stage/consumer.{type Batch, type Demand, Batch, Demand}

import kino/stage.{
  type ConsumerMessage, type DemandDispatcher, type ProducerConsumerMessage,
  type ProducerMessage, ConsumerMessage, ProducerMessage,
}
import kino/stage/internal/buffer.{type Buffer, type Take, Take}
import logging

pub type ProducerConsumer(in, out) {
  ProducerConsumer(
    subject: Subject(ProducerConsumerMessage(in, out)),
    consumer_subject: Subject(ConsumerMessage(in)),
    producer_subject: Subject(ProducerMessage(out)),
  )
}

pub type State(state, in, out) {
  State(
    self: Subject(ProducerConsumerMessage(in, out)),
    consumer_self: Subject(ConsumerMessage(in)),
    producer_self: Subject(ProducerMessage(out)),
    selector: Selector(ProducerConsumerMessage(in, out)),
    state: state,
    buffer: Buffer(out),
    dispatcher: DemandDispatcher(out),
    producers: Dict(Subject(ProducerMessage(in)), Demand),
    consumers: Set(Subject(ConsumerMessage(out))),
    producer_monitors: Dict(Subject(stage.ProducerMessage(in)), ProcessMonitor),
    consumer_monitors: Dict(Subject(stage.ConsumerMessage(out)), ProcessMonitor),
    events: Events(in),
    handle_events: fn(state, List(in)) -> stage.Produce(state, out),
  )
}

pub type Events(in) {
  Events(queue: Deque(#(List(in), Subject(ProducerMessage(in)))), demand: Int)
}

pub fn new(
  state: state,
  handle_events: fn(state, List(in)) -> stage.Produce(state, out),
) -> Result(ProducerConsumer(in, out), Dynamic) {
  let ack = process.new_subject()
  actor.start_spec(actor.Spec(
    init: fn() {
      let self = process.new_subject()
      let consumer_self = process.new_subject()
      let producer_self = process.new_subject()

      let ps =
        process.new_selector()
        |> process.selecting(producer_self, stage.ProducerMessage)
      let cs =
        process.new_selector()
        |> process.selecting(consumer_self, stage.ConsumerMessage)

      let selector =
        process.new_selector()
        |> process.selecting(self, function.identity)
        |> process.merge_selector(ps)
        |> process.merge_selector(cs)

      process.send(ack, #(self, consumer_self, producer_self))
      let state =
        State(
          self:,
          consumer_self:,
          producer_self:,
          selector:,
          state:,
          buffer: buffer.new(),
          dispatcher: stage.new_dispatcher(),
          consumers: set.new(),
          producers: dict.new(),
          consumer_monitors: dict.new(),
          producer_monitors: dict.new(),
          events: Events(queue: deque.new(), demand: 0),
          handle_events:,
        )
      actor.Ready(state, selector)
    },
    loop: handler,
    init_timeout: 5000,
  ))
  |> result.map(fn(_) {
    let #(self, consumer_self, producer_self) = process.receive_forever(ack)
    ProducerConsumer(self, consumer_self, producer_self)
  })
  |> result.map_error(dynamic.from)
}

pub fn handler(
  message: ProducerConsumerMessage(in, out),
  state: State(state, in, out),
) {
  case message {
    ProducerMessage(message) -> producer_handler(message, state)
    ConsumerMessage(message) -> consumer_handler(message, state)
  }
}

fn producer_handler(message: ProducerMessage(out), state: State(state, in, out)) {
  case message {
    stage.Subscribe(consumer, demand) -> {
      logging.log(
        logging.Debug,
        "ProducerConsumer: New consumer subscribing with demand "
          <> string.inspect(demand),
      )
      let consumers = set.insert(state.consumers, consumer)
      let mon = process.monitor_process(process.subject_owner(consumer))
      let selector =
        process.new_selector()
        |> process.selecting_process_down(mon, fn(_) {
          ProducerMessage(stage.ConsumerDown(consumer))
        })
        |> process.merge_selector(state.selector)
      process.send(state.producer_self, stage.Ask(demand, consumer))
      let dispatcher = stage.subscribe_dispatcher(state.dispatcher, consumer)
      let monitors = state.consumer_monitors |> dict.insert(consumer, mon)
      let state =
        State(
          ..state,
          selector:,
          consumers:,
          dispatcher:,
          consumer_monitors: monitors,
        )
      actor.continue(state) |> actor.with_selector(selector)
    }
    stage.Ask(demand:, consumer:) -> {
      let #(counter, dispatcher) =
        stage.ask_dispatcher(state.dispatcher, demand, consumer)

      let Events(queue, demand) = state.events
      let counter = counter + demand
      let state = State(..state, dispatcher:, events: Events(queue, counter))

      let #(from_buffer, state) = take_from_buffer(counter, state)
      logging.log(logging.Debug, "from_buffer: " <> string.inspect(from_buffer))
      let Events(queue, demand) = state.events
      take_events(queue, demand, state)
    }
    stage.Unsubscribe(consumer) -> {
      let consumers = set.delete(state.consumers, consumer)
      let monitors = case dict.get(state.consumer_monitors, consumer) {
        Ok(mon) -> {
          process.demonitor_process(mon)
          dict.delete(state.consumer_monitors, consumer)
        }
        _ -> state.consumer_monitors
      }
      let dispatcher = stage.cancel(state.dispatcher, consumer)
      let state =
        State(..state, consumers:, dispatcher:, consumer_monitors: monitors)
      actor.continue(state)
    }
    stage.ConsumerDown(consumer) -> {
      let consumers = set.delete(state.consumers, consumer)
      let monitors = dict.delete(state.consumer_monitors, consumer)
      let dispatcher = stage.cancel(state.dispatcher, consumer)
      let state =
        State(..state, consumers:, dispatcher:, consumer_monitors: monitors)
      actor.continue(state)
    }
  }
}

fn consumer_handler(message: ConsumerMessage(in), state: State(state, in, out)) {
  case message {
    stage.ConsumerSubscribe(source, min, max) -> {
      let producers =
        dict.insert(state.producers, source, Demand(current: max, min:, max:))
      let mon = process.monitor_process(process.subject_owner(source))
      let selector =
        process.new_selector()
        |> process.selecting_process_down(mon, fn(_) {
          ConsumerMessage(stage.ProducerDown(source))
        })
        |> process.merge_selector(state.selector)
      let monitors = state.producer_monitors |> dict.insert(source, mon)
      let state =
        State(..state, selector:, producers:, producer_monitors: monitors)
      process.send(source, stage.Subscribe(state.consumer_self, max))
      actor.continue(state) |> actor.with_selector(selector)
    }
    stage.NewEvents(events, from) -> {
      let queue = put_events(events, from, state.events.queue)
      take_events(queue, state.events.demand, state)
    }
    stage.ConsumerUnsubscribe(source) -> {
      let producers = dict.delete(state.producers, source)
      let monitors = case dict.get(state.producer_monitors, source) {
        Ok(mon) -> {
          process.demonitor_process(mon)
          dict.delete(state.producer_monitors, source)
        }
        _ -> state.producer_monitors
      }
      let state = State(..state, producers:, producer_monitors: monitors)
      process.send(source, stage.Unsubscribe(state.consumer_self))
      actor.continue(state)
    }
    stage.ProducerDown(source) -> {
      let producers = dict.delete(state.producers, source)
      let monitors = dict.delete(state.producer_monitors, source)
      let state = State(..state, producers:, producer_monitors: monitors)
      actor.continue(state)
    }
  }
}

fn dispatch_events(state: State(state, in, out), events: List(out), length: Int) {
  use <- bool.guard(events == [], { state })
  use <- bool.lazy_guard(set.is_empty(state.consumers), fn() {
    let buffer = buffer.store(state.buffer, events)
    State(..state, buffer:)
  })
  logging.log(logging.Debug, "dispatch_events: " <> string.inspect(events))
  let #(events, dispatcher) =
    stage.dispatch(state.dispatcher, state.producer_self, events, length)

  let Events(queue, demand) = state.events
  let demand = demand - { length - list.length(events) }

  let buffer = buffer.store(state.buffer, events)
  State(
    ..state,
    buffer: buffer,
    dispatcher: dispatcher,
    events: Events(queue, int.max(demand, 0)),
  )
}

fn take_events(
  queue: Deque(#(List(in), Subject(ProducerMessage(in)))),
  counter: Int,
  stage: State(state, in, out),
) -> actor.Next(ProducerConsumerMessage(in, out), State(state, in, out)) {
  use <- bool.lazy_guard(counter <= 0, fn() {
    let stage = State(..stage, events: Events(queue, counter))
    actor.continue(stage)
  })
  logging.log(logging.Debug, "take_events: " <> string.inspect(counter))
  case deque.pop_front(queue) {
    Ok(#(#(events, from), queue)) -> {
      let stage = State(..stage, events: Events(queue, counter))
      case send_events(events, from, stage) {
        actor.Continue(stage, _) ->
          take_events(stage.events.queue, stage.events.demand, stage)
        actor.Stop(reason) -> actor.Stop(reason)
      }
    }
    Error(_) -> {
      actor.continue(State(..stage, events: Events(queue, counter)))
    }
  }
}

fn put_events(events, from, queue) {
  deque.push_back(queue, #(events, from))
}

fn send_events(
  events: List(in),
  from: Subject(ProducerMessage(in)),
  stage: State(state, in, out),
) -> actor.Next(ProducerConsumerMessage(in, out), State(state, in, out)) {
  case dict.get(stage.producers, from) {
    Ok(demand) -> {
      let #(current, batches) = split_batches(events, demand)
      let demand = Demand(..demand, current:)
      let producers = dict.insert(stage.producers, from, demand)
      let state = State(..stage, producers:)
      dispatch(state, batches, from)
    }
    Error(_) -> {
      // We queued but producer was removed
      let batches = [Batch(events, 0)]
      dispatch(stage, batches, from)
    }
  }
}

fn dispatch(
  state: State(state, in, out),
  batches: List(Batch(in)),
  from: Subject(stage.ProducerMessage(in)),
) -> actor.Next(ProducerConsumerMessage(in, out), State(state, in, out)) {
  case batches {
    [] -> actor.continue(state)
    [Batch(events, size), ..rest] -> {
      case state.handle_events(state.state, events) {
        stage.Next(events, new_state) -> {
          let state = State(..state, state: new_state)
          let state = dispatch_events(state, events, list.length(events))
          process.send(from, stage.Ask(size, state.consumer_self))
          dispatch(state, rest, from)
        }
        stage.Done -> actor.Stop(process.Normal)
      }
    }
  }
}

fn split_batches(
  events: List(event),
  demand: Demand,
) -> #(Int, List(Batch(event))) {
  do_split_batches(
    events: events,
    min: demand.min,
    max: demand.max,
    old_demand: demand.current,
    new_demand: demand.current,
    batches: [],
  )
}

fn do_split_batches(
  events events: List(event),
  min min: Int,
  max max: Int,
  old_demand old_demand: Int,
  new_demand new_demand: Int,
  batches batches: List(Batch(event)),
) -> #(Int, List(Batch(event))) {
  use <- bool.lazy_guard(events == [], fn() {
    #(new_demand, list.reverse(batches))
  })

  let #(events, batch, batch_size) = split_events(events, max - min, 0, [])

  let #(old_demand, batch_size) = case old_demand - batch_size {
    diff if diff < 0 -> #(0, old_demand)
    diff -> #(diff, batch_size)
  }

  let #(new_demand, batch_size) = case new_demand - batch_size {
    diff if diff <= min -> #(max, max - diff)
    diff -> #(diff, 0)
  }

  do_split_batches(events, min, max, old_demand, new_demand, [
    Batch(batch, batch_size),
    ..batches
  ])
}

fn split_events(events: List(event), limit: Int, counter: Int, acc: List(event)) {
  use <- bool.lazy_guard(limit == counter, fn() {
    #(events, list.reverse(acc), counter)
  })

  case events {
    [] -> #([], list.reverse(acc), counter)
    [event, ..rest] -> {
      split_events(rest, limit, counter + 1, [event, ..acc])
    }
  }
}

fn take_from_buffer(
  demand: Int,
  state: State(state, in, out),
) -> #(Int, State(state, in, out)) {
  let Take(buffer, demand_left, events) = buffer.take(state.buffer, demand)
  case events {
    [] -> #(demand, state)
    _ -> {
      let state =
        dispatch_events(State(..state, buffer:), events, demand - demand_left)
      take_from_buffer(demand_left, state)
    }
  }
}
