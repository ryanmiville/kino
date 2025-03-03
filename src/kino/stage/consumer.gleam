import gleam/bool
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type ProcessMonitor, type Selector, type Subject}
import gleam/function

import gleam/list
import gleam/otp/actor
import gleam/result
import kino/stage.{
  ConsumerSubscribe, ConsumerUnsubscribe, NewEvents, ProducerDown,
}

pub type Consumer(event) {
  Consumer(subject: Subject(Message(event)))
}

type Message(event) =
  stage.ConsumerMessage(event)

pub type Demand {
  Demand(current: Int, min: Int, max: Int)
}

type State(state, event) {
  State(
    self: Subject(Message(event)),
    selector: Selector(Message(event)),
    state: state,
    handle_events: fn(state, List(event)) -> actor.Next(List(event), state),
    on_shutdown: fn(state) -> Nil,
    producers: Dict(Subject(stage.ProducerMessage(event)), Demand),
    monitors: Dict(Subject(stage.ProducerMessage(event)), ProcessMonitor),
  )
}

pub fn new_with_shutdown(
  state: state,
  handle_events: fn(state, List(event)) -> actor.Next(List(event), state),
  on_shutdown: fn(state) -> Nil,
) -> Result(Consumer(event), Dynamic) {
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
          self:,
          selector:,
          state:,
          handle_events: handle_events,
          on_shutdown: on_shutdown,
          producers: dict.new(),
          monitors: dict.new(),
        )
      actor.Ready(state, selector)
    },
    loop: handler,
    init_timeout: 5000,
  ))
  |> result.map(fn(_) {
    let subject = process.receive_forever(ack)
    Consumer(subject)
  })
  |> result.map_error(dynamic.from)
}

pub fn new(
  state: state,
  handle_events: fn(state, List(event)) -> actor.Next(List(event), state),
) -> Result(Consumer(event), Dynamic) {
  new_with_shutdown(state, handle_events, fn(_) { Nil })
}

fn handler(
  message: Message(event),
  state: State(state, event),
) -> actor.Next(Message(event), State(state, event)) {
  case message {
    ConsumerSubscribe(source, min, max) -> {
      let producers =
        dict.insert(state.producers, source, Demand(current: max, min:, max:))
      let mon = process.monitor_process(process.subject_owner(source))
      let selector =
        process.new_selector()
        |> process.selecting_process_down(mon, fn(_) { ProducerDown(source) })
        |> process.merge_selector(state.selector)

      let monitors = state.monitors |> dict.insert(source, mon)
      let state = State(..state, selector:, producers:, monitors:)
      process.send(source, stage.Subscribe(state.self, max))
      actor.continue(state) |> actor.with_selector(selector)
    }
    NewEvents(events:, from:) -> {
      case dict.get(state.producers, from) {
        Ok(demand) -> {
          let #(current, batches) = split_batches(events, demand)
          let demand = Demand(..demand, current:)
          let producers = dict.insert(state.producers, from, demand)
          let state = State(..state, producers:)
          dispatch(state, batches, from)
        }
        Error(_) -> actor.continue(state)
      }
    }
    ConsumerUnsubscribe(source) -> {
      let producers = dict.delete(state.producers, source)
      let monitors = case dict.get(state.monitors, source) {
        Ok(mon) -> {
          process.demonitor_process(mon)
          dict.delete(state.monitors, source)
        }
        _ -> state.monitors
      }
      let state = State(..state, producers:, monitors:)
      process.send(source, stage.Unsubscribe(state.self))
      case dict.is_empty(producers) {
        True -> {
          state.on_shutdown(state.state)
          actor.Stop(process.Normal)
        }
        False -> actor.continue(state)
      }
    }
    ProducerDown(source) -> {
      let producers = dict.delete(state.producers, source)
      let monitors = dict.delete(state.monitors, source)
      let state = State(..state, producers:, monitors:)
      case dict.is_empty(producers) {
        True -> {
          state.on_shutdown(state.state)
          actor.Stop(process.Normal)
        }
        False -> actor.continue(state)
      }
    }
  }
}

pub type Batch(event) {
  Batch(events: List(event), size: Int)
}

fn dispatch(
  state: State(state, event),
  batches: List(Batch(event)),
  from: Subject(stage.ProducerMessage(event)),
) -> actor.Next(Message(event), State(state, event)) {
  case batches {
    [] -> actor.continue(state)
    [Batch(events, size), ..rest] -> {
      case state.handle_events(state.state, events) {
        actor.Continue(new_state, _) -> {
          let state = State(..state, state: new_state)
          process.send(from, stage.Ask(size, state.self))
          dispatch(state, rest, from)
        }
        actor.Stop(reason) -> actor.Stop(reason)
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
