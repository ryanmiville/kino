import gleam/option.{type Option, None, Some}

pub type Actor(state, in, out) {
  Actor(
    state: state,
    handle_demand: fn(state) -> Option(out),
    handle_events: fn(state, in) -> Option(out),
  )
}

pub fn zip(
  initial_state: state,
  left: Actor(state1, in1, out1),
  right: Actor(state2, in2, out2),
) -> Actor(state, #(out1, out2), #(out1, out2)) {
  Actor(
    state: initial_state,
    handle_demand: fn(_state) -> Option(#(out1, out2)) {
      case left.handle_demand(left.state), right.handle_demand(right.state) {
        Some(out1), Some(out2) -> Some(#(out1, out2))
        _, _ -> None
      }
    },
    handle_events: fn(_state, msg: #(out1, out2)) -> Option(#(out1, out2)) {
      Some(msg)
    },
  )
}

pub type Msg(state, in, out) {
  Ask
}
