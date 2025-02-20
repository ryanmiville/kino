import gleam/bool
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/list

pub type Demand(event) =
  #(Subject(List(event)), Int)

pub type DemandDispatcher(event) {
  DemandDispatcher(demands: List(Demand(event)), pending: Int, max_demand: Int)
}

pub fn new() -> DemandDispatcher(event) {
  DemandDispatcher(demands: [], pending: 0, max_demand: 1000)
}

pub fn subscribe(
  dispatcher: DemandDispatcher(event),
  from: Subject(List(event)),
) {
  DemandDispatcher(
    demands: list.append(dispatcher.demands, [#(from, 0)]),
    pending: dispatcher.pending,
    max_demand: dispatcher.max_demand,
  )
}

pub fn cancel(dispatcher: DemandDispatcher(event), from: Subject(List(event))) {
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

pub fn ask(
  dispatcher: DemandDispatcher(event),
  counter: Int,
  from: Subject(List(event)),
) {
  let max = int.max(dispatcher.max_demand, counter)

  case counter > max {
    True ->
      io.println(
        "Dispatcher expects a max demand of "
        <> int.to_string(dispatcher.max_demand)
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
      max_demand: dispatcher.max_demand,
    )
  #(counter - already_sent, dispatcher)
}

pub fn dispatch(
  dispatcher: DemandDispatcher(event),
  events: List(event),
  length: Int,
) {
  let #(events, demands) = dispatch_demand(dispatcher.demands, events, length)
  #(events, DemandDispatcher(..dispatcher, demands:))
}

fn dispatch_demand(
  demands: List(Demand(event)),
  events: List(event),
  length: Int,
) {
  use <- bool.guard(events == [], #(events, demands))

  case demands {
    [] | [#(_, 0), ..] -> #(events, demands)
    [#(from, counter), ..rest] -> {
      let #(now, later, length, counter) = split_events(events, length, counter)
      process.send(from, now)
      let demands = add_demand(rest, from, counter)
      dispatch_demand(demands, later, length)
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
  from: Subject(List(event)),
  counter: Int,
) {
  case demands {
    [] -> [#(from, counter)]
    [#(_, current), ..] if counter > current -> [#(from, counter), ..demands]
    [demand, ..rest] -> [demand, ..add_demand(rest, from, counter)]
  }
}
