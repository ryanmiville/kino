import gleam/erlang/process
import gleam/otp/actor.{type StartError}
import gleam/result
import kino/stage/internal/stage
import kino/stage/internal/subscription.{type Subscription}

pub type Consumer(event) =
  stage.Consumer(event)

pub opaque type Builder(state, event) {
  Builder(
    init: fn() -> state,
    init_timeout: Int,
    subscriptions: List(Subscription(event)),
    handle_events: fn(state, List(event)) -> actor.Next(List(event), state),
    on_shutdown: fn(state) -> Nil,
  )
}

pub fn new(state: state) -> Builder(state, event) {
  Builder(
    init: fn() { state },
    init_timeout: 1000,
    subscriptions: [],
    handle_events: fn(_, _) { actor.Stop(process.Normal) },
    on_shutdown: fn(_) { Nil },
  )
}

pub fn new_with_init(timeout: Int, init: fn() -> state) -> Builder(state, event) {
  Builder(
    init: init,
    init_timeout: timeout,
    subscriptions: [],
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

// pub fn subscribe(
//   to producer: Subject(ProducerMessage(event)),
// ) -> Subscription(event) {
//   subscription.to(producer)
// }

pub fn min_demand(
  subscription: Subscription(event),
  min_demand: Int,
) -> Subscription(event) {
  subscription.min_demand(subscription, min_demand)
}

pub fn max_demand(
  subscription: Subscription(event),
  max_demand: Int,
) -> Subscription(event) {
  subscription.max_demand(subscription, max_demand)
}

pub fn add_subscription(
  builder: Builder(state, event),
  subscription: Subscription(event),
) -> Builder(state, event) {
  Builder(..builder, subscriptions: [subscription, ..builder.subscriptions])
}

pub fn start(
  builder: Builder(state, event),
) -> Result(Consumer(event), StartError) {
  let consumer =
    stage.start_consumer(
      init: builder.init,
      init_timeout: builder.init_timeout,
      handle_events: builder.handle_events,
      on_shutdown: builder.on_shutdown,
    )
  use consumer <- result.map(consumer)
  // list.each(builder.subscriptions, subscription.subscribe(consumer, _))
  consumer
}
