import gleam/bool
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}

pub type ProducerMessage(a) {
  Ask(demand: Int, consumer: Subject(ConsumerMessage(a)))
  Subscribe(consumer: Subject(ConsumerMessage(a)), demand: Int)
  Unsubscribe(consumer: Subject(ConsumerMessage(a)))
  ConsumerDown(consumer: Subject(ConsumerMessage(a)))
}

pub type ProducerConsumerMessage(in, out) {
  ConsumerMessage(ConsumerMessage(in))
  ProducerMessage(ProducerMessage(out))
}

pub type ConsumerMessage(a) {
  NewEvents(events: List(a), from: Subject(ProducerMessage(a)))
  ConsumerSubscribe(
    source: Subject(ProducerMessage(a)),
    min_demand: Int,
    max_demand: Int,
  )
  ConsumerUnsubscribe(source: Subject(ProducerMessage(a)))
  ProducerDown(producer: Subject(ProducerMessage(a)))
}

pub type Produce(state, a) {
  Next(elements: List(a), state: state)
  Done
}

pub fn subscribe(
  consumer consumer: Subject(ConsumerMessage(a)),
  to producer: Subject(ProducerMessage(a)),
  min_demand min_demand: Int,
  max_demand max_demand: Int,
) {
  process.send(consumer, ConsumerSubscribe(producer, min_demand, max_demand))
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
      io.println(
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

pub fn dispatch(
  dispatcher: DemandDispatcher(event),
  self: Subject(ProducerMessage(event)),
  events: List(event),
  length: Int,
) {
  let #(events, demands) =
    dispatch_demand(dispatcher.demands, self, events, length)
  #(events, DemandDispatcher(..dispatcher, demands:))
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
