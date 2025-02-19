import gleam/bool
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Subject}
import gleam/result
import gleam/set.{type Set}
import kino/gen_server.{type GenServer}
import kino/gen_stage/dispatcher.{type DemandDispatcher}
import kino/gen_stage/internal/buffer.{type Buffer, Take}

pub opaque type Source(a) {
  Source(server: GenServer(Message(a)))
}

pub type Message(a) {
  Ask(demand: Int, consumer: Subject(List(a)))
  Subscribe(consumer: Subject(List(a)), demand: Int)
}

type State(state, a) {
  State(
    state: state,
    buffer: Buffer(a),
    dispatcher: DemandDispatcher(a),
    consumers: Set(Subject(List(a))),
    pull: fn(state, Int) -> #(List(a), state),
  )
}

pub fn new(
  state: state,
  pull: fn(state, Int) -> #(List(a), state),
) -> Result(Source(a), Dynamic) {
  gen_server.new(fn(state) { gen_server.Ready(state) }, handler)
  |> gen_server.start_link(State(
    state: state,
    buffer: buffer.new(),
    dispatcher: dispatcher.new(),
    consumers: set.new(),
    pull: pull,
  ))
  |> result.map(Source)
}

fn handler(
  self: GenServer(Message(a)),
  message: Message(a),
  state: State(state, a),
) {
  case message {
    Subscribe(consumer, demand) -> {
      let consumers = set.insert(state.consumers, consumer)
      gen_server.cast(self, Ask(demand, consumer))
      let dispatcher = dispatcher.subscribe(state.dispatcher, consumer)
      gen_server.continue(State(..state, consumers:, dispatcher:))
    }
    Ask(demand:, consumer:) -> {
      ask_demand(demand, consumer, state)
    }
  }
}

fn ask_demand(demand: Int, consumer: Subject(List(a)), state: State(state, a)) {
  dispatcher.ask(state.dispatcher, demand, consumer)
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
  case take_from_buffer(demand, state) {
    #(0, state) -> {
      gen_server.continue(state)
    }
    #(demand, state) -> {
      let #(events, new_state) = state.pull(state.state, demand)
      let state = State(..state, state: new_state)
      let state = dispatch_events(state, events, demand)
      gen_server.continue(state)
    }
  }
}

fn take_from_buffer(demand: Int, state: State(state, event)) {
  let Take(buffer, demand_left, events) = buffer.take(state.buffer, demand)
  case events {
    [] -> #(demand, state)
    _ -> {
      let #(events, dispatcher) =
        dispatcher.dispatch(state.dispatcher, events, demand - demand_left)
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

  let #(events, dispatcher) =
    dispatcher.dispatch(state.dispatcher, events, length)
  let buffer = buffer.store(state.buffer, events)
  State(..state, buffer: buffer, dispatcher: dispatcher)
  // I think there's more to do here
}

pub fn subscribe(source: Source(a), subject: Subject(List(a)), demand: Int) {
  gen_server.cast(source.server, Subscribe(subject, demand))
}
