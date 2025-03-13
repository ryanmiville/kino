import gleam/option.{type Option, None, Some}
import gleam/otp/actor.{type StartError}
import kino/gen_stage/internal/stage
import kino/gen_stage/internal/subscription.{type Subscription}

pub type Processor(in, out) =
  stage.Processor(in, out)

pub fn as_consumer(processor: Processor(in, out)) {
  stage.as_consumer(processor)
}

pub fn as_producer(processor: Processor(in, out)) {
  stage.as_producer(processor)
}

pub type Produce(state, event) {
  Next(events: List(event), state: state)
  Done
}

pub type BufferStrategy {
  KeepFirst
  KeepLast
}

pub opaque type Builder(state, in, out) {
  Builder(
    init: fn() -> state,
    init_timeout: Int,
    subscriptions: List(Subscription(in)),
    handle_events: fn(state, List(in)) -> Produce(state, out),
    buffer_strategy: BufferStrategy,
    buffer_capacity: Option(Int),
  )
}

pub fn new(state: state) -> Builder(state, in, out) {
  Builder(
    init: fn() { state },
    init_timeout: 1000,
    subscriptions: [],
    handle_events: fn(_, _) { Done },
    buffer_strategy: KeepLast,
    buffer_capacity: None,
  )
}

pub fn new_with_init(
  timeout: Int,
  init: fn() -> state,
) -> Builder(state, in, out) {
  Builder(
    init: init,
    init_timeout: timeout,
    subscriptions: [],
    handle_events: fn(_, _) { Done },
    buffer_strategy: KeepLast,
    buffer_capacity: None,
  )
}

pub fn handle_events(
  builder: Builder(state, in, out),
  handle_events: fn(state, List(in)) -> Produce(state, out),
) -> Builder(state, in, out) {
  Builder(..builder, handle_events:)
}

pub fn buffer_strategy(
  builder: Builder(state, in, out),
  buffer_strategy: BufferStrategy,
) -> Builder(state, in, out) {
  Builder(..builder, buffer_strategy:)
}

pub fn buffer_capacity(
  builder: Builder(state, in, out),
  buffer_capacity: Int,
) -> Builder(state, in, out) {
  Builder(..builder, buffer_capacity: Some(buffer_capacity))
}

pub fn min_demand(
  subscription: Subscription(in),
  min_demand: Int,
) -> Subscription(in) {
  subscription.min_demand(subscription, min_demand)
}

pub fn max_demand(
  subscription: Subscription(in),
  max_demand: Int,
) -> Subscription(in) {
  subscription.max_demand(subscription, max_demand)
}

pub fn add_subscription(
  builder: Builder(state, in, out),
  subscription: Subscription(in),
) -> Builder(state, in, out) {
  Builder(..builder, subscriptions: [subscription, ..builder.subscriptions])
}

pub fn start(
  builder: Builder(state, in, out),
) -> Result(Processor(in, out), StartError) {
  stage.start_processor(
    init: builder.init,
    init_timeout: builder.init_timeout,
    handle_events: convert_handle(builder.handle_events),
    buffer_strategy: convert_buffer_strategy(builder.buffer_strategy),
    buffer_capacity: builder.buffer_capacity,
  )
}

fn convert_buffer_strategy(strategy: BufferStrategy) -> stage.BufferStrategy {
  case strategy {
    KeepFirst -> stage.KeepFirst
    KeepLast -> stage.KeepLast
  }
}

fn convert_handle(handle_events: fn(state, List(in)) -> Produce(state, out)) {
  fn(state, events) {
    handle_events(state, events)
    |> convert_produce
  }
}

fn convert_produce(
  produce: Produce(state, event),
) -> stage.Produce(state, event) {
  case produce {
    Next(events, state) -> stage.Next(events, state)
    Done -> stage.Done
  }
}
