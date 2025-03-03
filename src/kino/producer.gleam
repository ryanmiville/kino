import gleam/bool
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type ProcessMonitor, type Selector, type Subject}
import gleam/function
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import gleam/set.{type Set}

import logging

import kino/gen_stage.{
  type ConsumerMessage, type Produce, type ProducerMessage, Ask, ConsumerDown,
  Done, NewEvents, Next, Subscribe, Unsubscribe,
}
import kino/gen_stage/internal/buffer.{type Buffer, Take}

pub type Producer(a) {
  Producer(subject: Subject(ProducerMessage(a)))
}

type State(state, a) {
  State(
    self: Subject(ProducerMessage(a)),
    selector: Selector(ProducerMessage(a)),
    state: state,
    buffer: Buffer(a),
    dispatcher: DemandDispatcher(a),
    consumers: Set(Subject(ConsumerMessage(a))),
    monitors: Dict(Subject(ConsumerMessage(a)), ProcessMonitor),
    pull: fn(state, Int) -> Produce(state, a),
  )
}

pub fn new(
  state: state,
  pull: fn(state, Int) -> Produce(state, a),
) -> Result(Producer(a), Dynamic) {
  let ack = process.new_subject()
  actor.start_spec(actor.Spec(
    init: fn() {
      let self = process.new_subject()
      let selector =
        process.new_selector()
        |> process.selecting(self, function.identity)
      process.send(ack, self)
      let state =
        State(
          self: self,
          selector: selector,
          state: state,
          buffer: buffer.new() |> buffer.capacity(10_000),
          dispatcher: new_dispatcher(),
          consumers: set.new(),
          monitors: dict.new(),
          pull: pull,
        )
      actor.Ready(state, selector)
    },
    loop: handler,
    init_timeout: 5000,
  ))
  |> result.map(fn(_) {
    let subject = process.receive_forever(ack)
    Producer(subject)
  })
  |> result.map_error(dynamic.from)
}

fn handler(message: ProducerMessage(a), state: State(state, a)) {
  case message {
    Subscribe(consumer, demand) -> {
      let consumers = set.insert(state.consumers, consumer)
      let mon = process.monitor_process(process.subject_owner(consumer))
      let selector =
        process.new_selector()
        |> process.selecting_process_down(mon, fn(_) { ConsumerDown(consumer) })
        |> process.merge_selector(state.selector)
      process.send(state.self, Ask(demand, consumer))
      let dispatcher = subscribe_dispatcher(state.dispatcher, consumer)
      let monitors = state.monitors |> dict.insert(consumer, mon)
      let state = State(..state, selector:, consumers:, dispatcher:, monitors:)
      actor.continue(state) |> actor.with_selector(selector)
    }
    Ask(demand:, consumer:) -> {
      ask_demand(demand, consumer, state)
    }
    Unsubscribe(consumer) -> {
      // logging.log(logging.Debug, "unsub consumer")
      let consumers = set.delete(state.consumers, consumer)
      let monitors = case dict.get(state.monitors, consumer) {
        Ok(mon) -> {
          process.demonitor_process(mon)
          dict.delete(state.monitors, consumer)
        }
        _ -> state.monitors
      }
      let dispatcher = cancel(state.dispatcher, consumer)
      let state = State(..state, consumers:, dispatcher:, monitors:)
      actor.continue(state)
    }
    ConsumerDown(consumer) -> {
      // logging.log(logging.Debug, "consumer down")
      let consumers = set.delete(state.consumers, consumer)
      let monitors = dict.delete(state.monitors, consumer)
      let dispatcher = cancel(state.dispatcher, consumer)
      let state = State(..state, consumers:, dispatcher:, monitors:)
      actor.continue(state)
    }
  }
}

fn ask_demand(
  demand: Int,
  consumer: Subject(ConsumerMessage(a)),
  state: State(state, a),
) {
  ask_dispatcher(state.dispatcher, demand, consumer)
  |> handle_dispatcher_result(state)
}

fn handle_dispatcher_result(
  res: #(Int, DemandDispatcher(event)),
  state: State(state, event),
) {
  let #(counter, dispatcher) = res
  take_from_buffer_or_pull(counter, State(..state, dispatcher:))
}

fn take_from_buffer_or_pull(demand: Int, state: State(state, event)) {
  // logging.log(logging.Debug, "demand: " <> string.inspect(demand))
  case take_from_buffer(demand, state) {
    #(0, state) -> {
      // logging.log(logging.Debug, "continue from take")
      actor.continue(state)
    }
    #(demand, state) -> {
      // logging.log(logging.Debug, "pulling")
      case state.pull(state.state, demand) {
        Next(events, new_state) -> {
          let state = State(..state, state: new_state)
          let state = dispatch_events(state, events, list.length(events))
          actor.continue(state)
        }
        Done -> {
          // logging.log(logging.Debug, "called done")
          actor.Stop(process.Normal)
        }
      }
    }
  }
}

fn take_from_buffer(demand: Int, state: State(state, event)) {
  let Take(buffer, demand_left, events) = buffer.take(state.buffer, demand)
  case events {
    [] -> #(demand, state)
    _ -> {
      let #(events, dispatcher) = dispatch(state, events, demand - demand_left)
      let buffer = buffer.store(buffer, events)
      let state = State(..state, buffer: buffer, dispatcher: dispatcher)
      take_from_buffer(demand_left, state)
    }
  }
}

fn dispatch_events(state: State(state, event), events: List(event), length) {
  use <- bool.guard(events == [], state)
  use <- bool.lazy_guard(set.is_empty(state.consumers), fn() {
    let buffer = buffer.store(state.buffer, events)
    State(..state, buffer:)
  })

  let #(events, dispatcher) = dispatch(state, events, length)
  let buffer = buffer.store(state.buffer, events)
  State(..state, buffer: buffer, dispatcher: dispatcher)
}

//
// Dispatcher
//

pub type Demand(event) =
  #(Subject(ConsumerMessage(event)), Int)

pub type DemandDispatcher(event) {
  DemandDispatcher(
    demands: List(Demand(event)),
    pending: Int,
    max_demand: Option(Int),
  )
}

pub fn new_dispatcher() -> DemandDispatcher(event) {
  DemandDispatcher(demands: [], pending: 0, max_demand: None)
}

pub fn subscribe_dispatcher(
  dispatcher: DemandDispatcher(event),
  from: Subject(ConsumerMessage(event)),
) {
  DemandDispatcher(
    demands: list.append(dispatcher.demands, [#(from, 0)]),
    pending: dispatcher.pending,
    max_demand: dispatcher.max_demand,
  )
}

pub fn cancel(
  dispatcher: DemandDispatcher(event),
  from: Subject(ConsumerMessage(event)),
) {
  case list.key_pop(dispatcher.demands, from) {
    Error(Nil) -> dispatcher
    Ok(#(current, demands)) ->
      DemandDispatcher(
        demands: demands,
        pending: current + dispatcher.pending,
        max_demand: dispatcher.max_demand,
      )
  }
}

pub fn ask_dispatcher(
  dispatcher: DemandDispatcher(event),
  counter: Int,
  from: Subject(ConsumerMessage(event)),
) {
  let max = option.unwrap(dispatcher.max_demand, counter)

  case counter > max {
    True ->
      logging.log(
        logging.Debug,
        "Dispatcher expects a max demand of "
          <> int.to_string(max)
          <> " but got demand for "
          <> int.to_string(counter)
          <> " events",
      )
    _ -> Nil
  }
  let demands = case list.key_pop(dispatcher.demands, from) {
    Error(Nil) -> dispatcher.demands
    Ok(#(current, demands)) -> {
      add_demand(demands, from, current + counter)
    }
  }
  let already_sent = int.min(dispatcher.pending, counter)
  let dispatcher =
    DemandDispatcher(
      demands:,
      pending: dispatcher.pending - already_sent,
      max_demand: Some(max),
    )
  #(counter - already_sent, dispatcher)
}

fn dispatch(state: State(state, event), events: List(event), length: Int) {
  let #(events, demands) =
    dispatch_demand(state.dispatcher.demands, state.self, events, length)
  #(events, DemandDispatcher(..state.dispatcher, demands:))
}

fn dispatch_demand(
  demands: List(Demand(event)),
  self: Subject(ProducerMessage(event)),
  events: List(event),
  length: Int,
) {
  use <- bool.guard(events == [], #(events, demands))

  case demands {
    [] | [#(_, 0), ..] -> #(events, demands)
    [#(from, counter), ..rest] -> {
      let #(now, later, length, counter) = split_events(events, length, counter)
      process.send(from, NewEvents(now, self))
      let demands = add_demand(rest, from, counter)
      dispatch_demand(demands, self, later, length)
    }
  }
}

pub fn split_events(events: List(event), length: Int, counter: Int) {
  case length <= counter {
    True -> #(events, [], 0, counter - length)
    False -> {
      let #(now, later) = list.split(events, counter)
      #(now, later, length - counter, 0)
    }
  }
}

fn add_demand(
  demands: List(Demand(event)),
  from: Subject(ConsumerMessage(event)),
  counter: Int,
) {
  case demands {
    [] -> [#(from, counter)]
    [#(_, current), ..] if counter > current -> [#(from, counter), ..demands]
    [demand, ..rest] -> [demand, ..add_demand(rest, from, counter)]
  }
}
