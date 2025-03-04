import gleam/bool
import gleam/dict.{type Dict}
import gleam/erlang/process.{type ProcessMonitor, type Selector, type Subject}
import gleam/function
import gleam/list
import gleam/otp/actor.{type StartError}
import gleam/result
import gleam/set.{type Set}
import kino/stage.{type Produce, Done, Next}
import kino/stage/internal/buffer.{type Buffer, Take}
import kino/stage/internal/dispatcher.{type DemandDispatcher, DemandDispatcher}
import kino/stage/internal/stage.{type ProducerMessage} as internal

pub type Producer(event) =
  Subject(ProducerMessage(event))

pub type BufferStrategy {
  KeepFirst
  KeepLast
}

pub opaque type Builder(state, event) {
  Builder(
    init: fn() -> state,
    init_timeout: Int,
    pull: fn(state, Int) -> Produce(state, event),
    buffer_strategy: BufferStrategy,
    buffer_capacity: Int,
  )
}

pub fn new(state: state) -> Builder(state, event) {
  Builder(
    init: fn() { state },
    init_timeout: 1000,
    pull: fn(_, _) { Done },
    buffer_strategy: KeepLast,
    buffer_capacity: 10_000,
  )
}

pub fn new_with_init(timeout: Int, init: fn() -> state) -> Builder(state, event) {
  Builder(
    init: init,
    init_timeout: timeout,
    pull: fn(_, _) { Done },
    buffer_strategy: KeepLast,
    buffer_capacity: 10_000,
  )
}

pub fn pull(
  builder: Builder(state, event),
  pull: fn(state, Int) -> Produce(state, event),
) -> Builder(state, event) {
  Builder(..builder, pull:)
}

pub fn buffer_strategy(
  builder: Builder(state, event),
  buffer_strategy: BufferStrategy,
) -> Builder(state, event) {
  Builder(..builder, buffer_strategy:)
}

pub fn buffer_capacity(
  builder: Builder(state, event),
  buffer_capacity: Int,
) -> Builder(state, event) {
  Builder(..builder, buffer_capacity:)
}

pub fn start(
  builder: Builder(state, event),
) -> Result(Producer(event), StartError) {
  let ack = process.new_subject()
  actor.start_spec(actor.Spec(
    init: fn() {
      let state = builder.init()
      let buf = buffer.new() |> buffer.capacity(builder.buffer_capacity)
      let self = process.new_subject()
      let buffer = case builder.buffer_strategy {
        KeepFirst -> buffer.keep(buf, buffer.First)
        KeepLast -> buffer.keep(buf, buffer.Last)
      }
      let selector =
        process.new_selector()
        |> process.selecting(self, function.identity)
      process.send(ack, self)
      let state =
        internal.ProducerState(
          self: self,
          selector: selector,
          state: state,
          buffer: buffer,
          dispatcher: internal.new_dispatcher(),
          consumers: set.new(),
          monitors: dict.new(),
          pull: builder.pull,
        )
      actor.Ready(state, selector)
    },
    loop: internal.producer_on_message,
    init_timeout: builder.init_timeout,
  ))
  |> result.map(fn(_) { process.receive_forever(ack) })
}
// type State(state, event) {
//   State(
//     self: Subject(ProducerMessage(event)),
//     selector: Selector(ProducerMessage(event)),
//     state: state,
//     buffer: Buffer(event),
//     dispatcher: DemandDispatcher(event),
//     consumers: Set(Subject(ConsumerMessage(event))),
//     monitors: Dict(Subject(ConsumerMessage(event)), ProcessMonitor),
//     pull: fn(state, Int) -> Produce(state, event),
//   )
// }

// fn on_message(message: ProducerMessage(event), state: State(state, event)) {
//   case message {
//     Subscribe(consumer, demand) -> {
//       let consumers = set.insert(state.consumers, consumer)
//       let mon = process.monitor_process(process.subject_owner(consumer))
//       let selector =
//         process.new_selector()
//         |> process.selecting_process_down(mon, fn(_) { ConsumerDown(consumer) })
//         |> process.merge_selector(state.selector)
//       process.send(state.self, Ask(demand, consumer))
//       let dispatcher = dispatcher.subscribe(state.dispatcher, consumer)
//       let monitors = state.monitors |> dict.insert(consumer, mon)
//       let state = State(..state, selector:, consumers:, dispatcher:, monitors:)
//       actor.continue(state) |> actor.with_selector(selector)
//     }
//     Ask(demand:, consumer:) -> {
//       ask_demand(demand, consumer, state)
//     }
//     Unsubscribe(consumer) -> {
//       let consumers = set.delete(state.consumers, consumer)
//       let monitors = case dict.get(state.monitors, consumer) {
//         Ok(mon) -> {
//           process.demonitor_process(mon)
//           dict.delete(state.monitors, consumer)
//         }
//         _ -> state.monitors
//       }
//       let dispatcher = dispatcher.cancel(state.dispatcher, consumer)
//       let state = State(..state, consumers:, dispatcher:, monitors:)
//       actor.continue(state)
//     }
//     ConsumerDown(consumer) -> {
//       let consumers = set.delete(state.consumers, consumer)
//       let monitors = dict.delete(state.monitors, consumer)
//       let dispatcher = dispatcher.cancel(state.dispatcher, consumer)
//       let state = State(..state, consumers:, dispatcher:, monitors:)
//       actor.continue(state)
//     }
//   }
// }

// fn ask_demand(
//   demand: Int,
//   consumer: Subject(ConsumerMessage(event)),
//   state: State(state, event),
// ) {
//   dispatcher.ask(state.dispatcher, demand, consumer)
//   |> handle_dispatcher_result(state)
// }

// fn handle_dispatcher_result(
//   res: #(Int, DemandDispatcher(event)),
//   state: State(state, event),
// ) {
//   let #(counter, dispatcher) = res
//   take_from_buffer_or_pull(counter, State(..state, dispatcher:))
// }

// fn take_from_buffer_or_pull(demand: Int, state: State(state, event)) {
//   case take_from_buffer(demand, state) {
//     #(0, state) -> {
//       actor.continue(state)
//     }
//     #(demand, state) -> {
//       case state.pull(state.state, demand) {
//         Next(events, new_state) -> {
//           let state = State(..state, state: new_state)
//           let state = dispatch_events(state, events, list.length(events))
//           actor.continue(state)
//         }
//         Done -> {
//           actor.Stop(process.Normal)
//         }
//       }
//     }
//   }
// }

// fn take_from_buffer(demand: Int, state: State(state, event)) {
//   let Take(buffer, demand_left, events) = buffer.take(state.buffer, demand)
//   case events {
//     [] -> #(demand, state)
//     _ -> {
//       let #(events, dispatcher) =
//         dispatcher.dispatch(
//           state.dispatcher,
//           state.self,
//           events,
//           demand - demand_left,
//         )
//       let buffer = buffer.store(buffer, events)
//       let state = State(..state, buffer: buffer, dispatcher: dispatcher)
//       take_from_buffer(demand_left, state)
//     }
//   }
// }

// fn dispatch_events(state: State(state, event), events: List(event), length) {
//   use <- bool.guard(events == [], state)
//   use <- bool.lazy_guard(set.is_empty(state.consumers), fn() {
//     let buffer = buffer.store(state.buffer, events)
//     State(..state, buffer:)
//   })

//   let #(events, dispatcher) =
//     dispatcher.dispatch(state.dispatcher, state.self, events, length)
//   let buffer = buffer.store(state.buffer, events)
//   State(..state, buffer: buffer, dispatcher: dispatcher)
// }
