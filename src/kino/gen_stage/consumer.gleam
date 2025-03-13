import gleam/erlang/process
import gleam/otp/actor.{type StartError}
import kino/gen_stage/internal/stage
import kino/gen_stage/internal/subscription.{type Subscription}

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

pub fn add_subscription(
  builder: Builder(state, event),
  subscription: Subscription(event),
) -> Builder(state, event) {
  Builder(..builder, subscriptions: [subscription, ..builder.subscriptions])
}

pub fn start(
  builder: Builder(state, event),
) -> Result(Consumer(event), StartError) {
  stage.start_consumer(
    init: builder.init,
    init_timeout: builder.init_timeout,
    handle_events: builder.handle_events,
    on_shutdown: builder.on_shutdown,
  )
}
