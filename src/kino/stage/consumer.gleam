import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type ProcessMonitor, type Selector, type Subject}
import gleam/function

import gleam/otp/actor
import gleam/result
import kino/stage.{
  ConsumerSubscribe, ConsumerUnsubscribe, NewEvents, ProducerDown,
}
import kino/stage/internal/batch.{type Batch, type Demand, Batch, Demand}

pub type Consumer(event) {
  Consumer(subject: Subject(Message(event)))
}

type Message(event) =
  stage.ConsumerMessage(event)

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
          let #(current, batches) = batch.events(events, demand)
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
