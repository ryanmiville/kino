import gleam/dict.{type Dict}
import gleam/erlang/process.{type ProcessMonitor, type Selector, type Subject}
import gleam/function
import gleam/otp/actor.{type StartError}
import gleam/result
import kino/stage/internal/batch.{type Batch, type Demand, Batch, Demand}
import kino/stage/internal/stage.{
  type ConsumerMessage, ConsumerSubscribe, ConsumerUnsubscribe, NewEvents,
  ProducerDown,
}

pub type Consumer(event) =
  Subject(ConsumerMessage(event))

pub opaque type Builder(state, event) {
  Builder(
    init: fn() -> state,
    init_timeout: Int,
    handle_events: fn(state, List(event)) -> actor.Next(List(event), state),
    on_shutdown: fn(state) -> Nil,
  )
}

pub fn new(state: state) -> Builder(state, event) {
  Builder(
    init: fn() { state },
    init_timeout: 1000,
    handle_events: fn(_, _) { actor.Stop(process.Normal) },
    on_shutdown: fn(_) { Nil },
  )
}

pub fn new_with_init(timeout: Int, init: fn() -> state) -> Builder(state, event) {
  Builder(
    init: init,
    init_timeout: timeout,
    handle_events: fn(_, _) { actor.Stop(process.Normal) },
    on_shutdown: fn(_) { Nil },
  )
}

pub fn handle_events(
  builder: Builder(state, event),
  handle_events: fn(state, List(event)) -> actor.Next(List(event), state),
) -> Builder(state, event) {
  Builder(..builder, handle_events:)
}

pub fn on_shutdown(
  builder: Builder(state, event),
  on_shutdown: fn(state) -> Nil,
) -> Builder(state, event) {
  Builder(..builder, on_shutdown:)
}

pub fn start(
  builder: Builder(state, event),
) -> Result(Consumer(event), StartError) {
  let ack = process.new_subject()
  actor.start_spec(actor.Spec(
    init: fn() {
      let state = builder.init()
      let self = process.new_subject()
      let selector =
        process.new_selector()
        |> process.selecting(self, function.identity)
      process.send(ack, self)
      let state =
        stage.ConsumerState(
          self:,
          selector:,
          state:,
          handle_events: builder.handle_events,
          on_shutdown: builder.on_shutdown,
          producers: dict.new(),
          monitors: dict.new(),
        )
      actor.Ready(state, selector)
    },
    loop: stage.consumer_on_message,
    init_timeout: builder.init_timeout,
  ))
  |> result.map(fn(_) { process.receive_forever(ack) })
}
// type State(state, event) {
//   State(
//     self: Subject(ConsumerMessage(event)),
//     selector: Selector(ConsumerMessage(event)),
//     state: state,
//     handle_events: fn(state, List(event)) -> actor.Next(List(event), state),
//     on_shutdown: fn(state) -> Nil,
//     producers: Dict(Subject(stage.ProducerMessage(event)), Demand),
//     monitors: Dict(Subject(stage.ProducerMessage(event)), ProcessMonitor),
//   )
// }

// fn on_message(
//   message: ConsumerMessage(event),
//   state: State(state, event),
// ) -> actor.Next(ConsumerMessage(event), State(state, event)) {
//   case message {
//     ConsumerSubscribe(source, min, max) -> {
//       let producers =
//         dict.insert(state.producers, source, Demand(current: max, min:, max:))
//       let mon = process.monitor_process(process.subject_owner(source))
//       let selector =
//         process.new_selector()
//         |> process.selecting_process_down(mon, fn(_) { ProducerDown(source) })
//         |> process.merge_selector(state.selector)

//       let monitors = state.monitors |> dict.insert(source, mon)
//       let state = State(..state, selector:, producers:, monitors:)
//       process.send(source, stage.Subscribe(state.self, max))
//       actor.continue(state) |> actor.with_selector(selector)
//     }
//     NewEvents(events:, from:) -> {
//       case dict.get(state.producers, from) {
//         Ok(demand) -> {
//           let #(current, batches) = batch.events(events, demand)
//           let demand = Demand(..demand, current:)
//           let producers = dict.insert(state.producers, from, demand)
//           let state = State(..state, producers:)
//           dispatch(state, batches, from)
//         }
//         Error(_) -> actor.continue(state)
//       }
//     }
//     ConsumerUnsubscribe(source) -> {
//       let producers = dict.delete(state.producers, source)
//       let monitors = case dict.get(state.monitors, source) {
//         Ok(mon) -> {
//           process.demonitor_process(mon)
//           dict.delete(state.monitors, source)
//         }
//         _ -> state.monitors
//       }
//       let state = State(..state, producers:, monitors:)
//       process.send(source, stage.Unsubscribe(state.self))
//       case dict.is_empty(producers) {
//         True -> {
//           state.on_shutdown(state.state)
//           actor.Stop(process.Normal)
//         }
//         False -> actor.continue(state)
//       }
//     }
//     ProducerDown(source) -> {
//       let producers = dict.delete(state.producers, source)
//       let monitors = dict.delete(state.monitors, source)
//       let state = State(..state, producers:, monitors:)
//       case dict.is_empty(producers) {
//         True -> {
//           state.on_shutdown(state.state)
//           actor.Stop(process.Normal)
//         }
//         False -> actor.continue(state)
//       }
//     }
//   }
// }

// fn dispatch(
//   state: State(state, event),
//   batches: List(Batch(event)),
//   from: Subject(stage.ProducerMessage(event)),
// ) -> actor.Next(ConsumerMessage(event), State(state, event)) {
//   case batches {
//     [] -> actor.continue(state)
//     [Batch(events, size), ..rest] -> {
//       case state.handle_events(state.state, events) {
//         actor.Continue(new_state, _) -> {
//           let state = State(..state, state: new_state)
//           process.send(from, stage.Ask(size, state.self))
//           dispatch(state, rest, from)
//         }
//         actor.Stop(reason) -> actor.Stop(reason)
//       }
//     }
//   }
// }
