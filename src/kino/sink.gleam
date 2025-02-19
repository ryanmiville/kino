import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/result

pub type Sink(event) {
  Sink(subject: Subject(List(event)))
}

type State(state, event) {
  State(
    state: state,
    handle_events: fn(state, List(event)) -> actor.Next(List(event), state),
  )
}

pub fn new(
  state: state,
  handle_events: fn(state, List(event)) -> actor.Next(List(event), state),
) -> Result(Sink(event), Dynamic) {
  actor.start(State(state, handle_events), handler(handle_events))
  |> result.map(Sink)
  |> result.map_error(dynamic.from)
}

fn handler(
  handle_events: fn(state, List(event)) -> actor.Next(List(event), state),
) {
  fn(message: List(event), state: State(state, event)) -> actor.Next(
    List(event),
    State(state, event),
  ) {
    case handle_events(state.state, message) {
      actor.Continue(new_state, selector) ->
        actor.Continue(State(..state, state: new_state), selector)
      actor.Stop(reason) -> actor.Stop(reason)
    }
  }
}
