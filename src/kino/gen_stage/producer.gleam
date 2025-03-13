import gleam/otp/actor.{type StartError}
import kino/gen_stage/internal/stage

pub type Producer(event) =
  stage.Producer(event)

pub type Produce(state, event) {
  Next(events: List(event), state: state)
  Done
}

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
  stage.start_producer(
    init: builder.init,
    init_timeout: builder.init_timeout,
    pull: convert_pull(builder.pull),
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

fn convert_pull(pull: fn(state, Int) -> Produce(state, event)) {
  fn(state, events) {
    pull(state, events)
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
