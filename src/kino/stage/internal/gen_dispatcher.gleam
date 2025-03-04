import gleam/bool
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import logging

pub type Demand(consumer) =
  #(Subject(consumer), Int)

pub type Message(event, producer, consumer) =
  fn(List(event), Subject(producer)) -> consumer

pub type DemandDispatcher(event, producer, consumer) {
  DemandDispatcher(
    demands: List(Demand(consumer)),
    pending: Int,
    max_demand: Option(Int),
    message: Message(event, producer, consumer),
  )
}

pub fn new(
  message: Message(event, producer, consumer),
) -> DemandDispatcher(event, producer, consumer) {
  DemandDispatcher(demands: [], pending: 0, max_demand: None, message:)
}

pub fn subscribe(
  dispatcher: DemandDispatcher(event, producer, consumer),
  from: Subject(consumer),
) {
  DemandDispatcher(
    demands: list.append(dispatcher.demands, [#(from, 0)]),
    pending: dispatcher.pending,
    max_demand: dispatcher.max_demand,
    message: dispatcher.message,
  )
}

pub fn cancel(
  dispatcher: DemandDispatcher(event, producer, consumer),
  from: Subject(consumer),
) {
  case list.key_pop(dispatcher.demands, from) {
    Error(Nil) -> dispatcher
    Ok(#(current, demands)) ->
      DemandDispatcher(
        ..dispatcher,
        demands: demands,
        pending: current + dispatcher.pending,
        max_demand: dispatcher.max_demand,
      )
  }
}

pub fn ask(
  dispatcher: DemandDispatcher(event, producer, consumer),
  counter: Int,
  from: Subject(consumer),
) {
  let max = option.unwrap(dispatcher.max_demand, counter)

  case counter > max {
    True ->
      logging.log(
        logging.Warning,
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
      ..dispatcher,
      demands:,
      pending: dispatcher.pending - already_sent,
      max_demand: Some(max),
    )
  #(counter - already_sent, dispatcher)
}

pub fn dispatch(
  dispatcher: DemandDispatcher(event, producer, consumer),
  self: Subject(producer),
  events: List(event),
  length: Int,
) {
  let #(events, demands) =
    dispatch_demand(
      dispatcher.demands,
      self,
      events,
      length,
      dispatcher.message,
    )
  #(events, DemandDispatcher(..dispatcher, demands:))
}

fn dispatch_demand(
  demands: List(Demand(consumer)),
  self: Subject(producer),
  events: List(event),
  length: Int,
  message: Message(event, producer, consumer),
) {
  use <- bool.guard(events == [], #(events, demands))

  case demands {
    [] | [#(_, 0), ..] -> #(events, demands)
    [#(from, counter), ..rest] -> {
      let #(now, later, length, counter) = split_events(events, length, counter)
      process.send(from, message(now, self))
      let demands = add_demand(rest, from, counter)
      dispatch_demand(demands, self, later, length, message)
    }
  }
}

fn split_events(events: List(event), length: Int, counter: Int) {
  case length <= counter {
    True -> #(events, [], 0, counter - length)
    False -> {
      let #(now, later) = list.split(events, counter)
      #(now, later, length - counter, 0)
    }
  }
}

fn add_demand(
  demands: List(Demand(consumer)),
  from: Subject(consumer),
  counter: Int,
) {
  case demands {
    [] -> [#(from, counter)]
    [#(_, current), ..] if counter > current -> [#(from, counter), ..demands]
    [demand, ..rest] -> [demand, ..add_demand(rest, from, counter)]
  }
}
