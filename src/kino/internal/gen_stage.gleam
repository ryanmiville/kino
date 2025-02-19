import gleam/bool
import gleam/dict.{type Dict}
import gleam/erlang.{type Reference}
import gleam/erlang/atom.{type Atom}
import gleam/int
import gleam/list
import gleam/option.{type Option, None}
import kino/gen_server.{type GenServer, type InitResult, type Next}
import kino/gen_stage/dispatcher.{type DemandDispatcher}
import kino/gen_stage/internal/buffer.{type Buffer}
import kino/gen_stage/internal/message.{
  type DemandMode, type Message, AskDemand, ConsumerSubscribe,
  EstimateBufferCount, GetDemandMode, ProducerSubscribe, SendEvents,
  SetDemandMode,
}

pub type From(reply) =
  gen_server.From(reply)

pub type Kind {
  Producer
  ProducerConsumer
  Consumer
}

pub type Events(event) {
  Events(events: List(event), counter: Int)
}

pub type State(state, event) {
  State(
    kind: Kind,
    state: state,
    buffer: Buffer(event),
    dispatcher: DemandDispatcher(event),
    mode: DemandMode,
    events: Events(event),
    producers: Dict(Reference, GenStage(event)),
    consumers: Dict(Reference, GenStage(event)),
  )
}

pub type Builder(args, event, state) {
  Builder(
    init: fn(args) -> InitResult(State(state, event)),
    handle_demand: fn(Int, state) -> Next(state),
    handle_events: fn(List(event), state) -> Next(state),
    name: Option(Atom),
  )
}

pub type GenStage(event) =
  GenServer(Message(event))

pub fn start_link(builder: Builder(args, event, state), args: args) {
  builder
  |> build_server
  |> gen_server.start_link(args)
}

fn build_server(builder: Builder(args, event, state)) {
  gen_server.Spec(
    init: builder.init,
    handler: handler(builder.handle_demand, builder.handle_events),
    handle_timeout: None,
    handle_process_down: None,
    name: builder.name,
  )
}

fn handler(
  handle_demand: fn(Int, state) -> Next(state),
  handle_events: fn(List(event), state) -> Next(state),
) -> fn(GenStage(event), Message(event), State(state, event)) ->
  Next(State(state, event)) {
  fn(self, message, state) {
    case message {
      AskDemand(demand, consumer) -> ask_demand(demand, consumer, state)

      GetDemandMode(from) -> get_demand_mode(state, from)

      SetDemandMode(mode) -> set_demand_mode(state, mode)

      SendEvents(events) -> send_events(state, events)

      ConsumerSubscribe(producer, from) ->
        consumer_subscribe(self, state, producer, from)

      ProducerSubscribe(consumer) -> producer_subscribe(state, consumer)

      EstimateBufferCount(from) -> estimate_buffer_count(state, from)
    }
  }
}

pub fn init_producer(
  init: fn(args) -> InitResult(state),
) -> fn(args) -> InitResult(State(state, event)) {
  todo
}

pub fn init_producer_consumer(
  init: fn(args) -> InitResult(state),
) -> fn(args) -> InitResult(State(state, event)) {
  todo
}

pub fn init_consumer(
  init: fn(args) -> InitResult(state),
) -> fn(args) -> InitResult(State(state, event)) {
  todo
}

fn ask_demand(
  demand: Int,
  consumer: GenStage(event),
  state: State(state, event),
) -> Next(State(state, event)) {
  dispatcher.ask(state.dispatcher, demand, todo)
  |> handle_dispatcher_result(state)
}

fn get_demand_mode(
  state: State(state, event),
  from: From(DemandMode),
) -> Next(State(state, event)) {
  gen_server.reply(from, state.mode)
  gen_server.continue(state)
}

fn set_demand_mode(
  state: State(state, event),
  mode: DemandMode,
) -> Next(State(state, event)) {
  gen_server.continue(State(..state, mode:))
}

fn send_events(
  state: State(state, event),
  events: List(event),
) -> Next(State(state, event)) {
  todo
}

fn consumer_subscribe(
  self: GenStage(event),
  state: State(state, event),
  producer: GenStage(event),
  from: From(Bool),
) -> Next(State(state, event)) {
  case state.kind {
    Producer -> panic as "Called consumer_subscribe on a producer"
    _ -> {
      // todo remove ref
      let producers =
        dict.insert(state.producers, erlang.make_reference(), producer)
      gen_server.cast(producer, ProducerSubscribe(self))
      gen_server.cast(producer, AskDemand(1000, self))
      gen_server.reply(from, True)
      gen_server.continue(State(..state, producers:))
    }
  }
}

fn producer_subscribe(
  state: State(state, event),
  consumer: GenStage(event),
) -> Next(State(state, event)) {
  case state.kind {
    Consumer -> panic as "Called producer_subscribe on a consumer"
    _ -> {
      let consumers =
        dict.insert(state.consumers, erlang.make_reference(), consumer)
      gen_server.continue(State(..state, consumers:))
    }
  }
}

fn estimate_buffer_count(
  state: State(state, event),
  from: From(Int),
) -> Next(State(state, event)) {
  gen_server.reply(from, buffer.estimate_count(state.buffer))
  gen_server.continue(state)
}

fn handle_dispatcher_result(
  res: #(Int, DemandDispatcher(event)),
  state: State(state, event),
) {
  let #(counter, dispatcher) = res
  case state.kind {
    ProducerConsumer -> {
      let counter = state.events.counter + counter
      let state =
        State(..state, dispatcher:, events: Events(..state.events, counter:))
      let #(_, state) = take_from_buffer(counter, state)
      take_pc_events(state.events.events, state.events.counter, state)
    }
    Producer -> todo
    Consumer -> panic as "Received dispatcher result in consumer"
  }
  todo
}

fn take_from_buffer(counter, state: State(state, event)) {
  case buffer.take(state.buffer, counter) {
    buffer.Take(_, _, []) -> #(counter, state)
    buffer.Take(buffer, new_counter, events) -> {
      let state = State(..state, buffer:)
      let state = dispatch_events(events, counter - new_counter, state)
      //dispatch_info fold
      take_from_buffer(new_counter, state)
    }
  }
}

fn take_pc_events(events, counter, state) {
  todo
}

fn dispatch_events(
  events: List(event),
  counter: Int,
  state: State(state, event),
) {
  use <- bool.guard(events == [], state)

  use <- bool.lazy_guard(state.mode == message.Accumulate, fn() {
    dispatch_events_accumulating(events, counter, state)
  })

  use <- bool.lazy_guard(dict.is_empty(state.consumers), fn() {
    buffer_events(events, state)
  })

  let #(events, dispatcher) =
    dispatcher.dispatch(state.dispatcher, events, counter)

  let state = case state.kind {
    ProducerConsumer -> {
      let Events(queue, demand) = state.events
      let demand = demand - { counter - list.length(events) }
      State(..state, dispatcher:, events: Events(queue, int.max(demand, 0)))
    }
    _ -> State(..state, dispatcher:)
  }

  buffer_events(events, state)
}

fn dispatch_events_accumulating(
  events: List(event),
  counter: Int,
  state: State(state, event),
) {
  let events = list.append(events, state.events.events)
  State(..state, events: Events(events, counter))
}

fn buffer_events(events, state: State(state, event)) {
  use <- bool.guard(events == [], state)
  let buffer = buffer.store(state.buffer, events)
  //fold dispatch_info
  State(..state, buffer:)
}
