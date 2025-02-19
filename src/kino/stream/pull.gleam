import gleam/deque.{type Deque}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Subject}
import gleam/result
import kino/gen_server.{type GenServer}
import kino/gen_stage/internal/buffer.{type Buffer, Take}

pub opaque type Pull(a) {
  Pull(server: GenServer(Message(a)))
}

pub type Message(a) {
  EmitEvents(demand: Int, consumer: Subject(List(a)))
  DoPull(demand: Int)
}

type State(state, a) {
  State(
    state: state,
    buffer: Buffer(a),
    consumers: Deque(#(Int, Subject(List(a)))),
  )
}

pub fn new(
  state: state,
  pull: fn(state, Int) -> #(List(a), state),
) -> Result(Pull(a), Dynamic) {
  gen_server.new(fn(state) { gen_server.Ready(state) }, handler(pull))
  |> gen_server.start_link(State(
    state,
    buffer: buffer.new(),
    consumers: deque.new(),
  ))
  |> result.map(Pull)
}

fn handler(pull: fn(state, Int) -> #(List(a), state)) {
  fn(self: GenServer(Message(a)), message: Message(a), state: State(state, a)) {
    case message {
      EmitEvents(demand, _) if demand <= 0 -> {
        gen_server.continue(state)
      }

      EmitEvents(demand:, consumer:) -> {
        let Take(buffer, demand_left, events) =
          buffer.take(state.buffer, demand)

        case events {
          [] -> Nil
          _ -> process.send(consumer, events)
        }

        let state = State(..state, buffer:)

        case demand_left {
          0 -> gen_server.continue(state)
          _ -> {
            gen_server.cast(self, DoPull(demand_left))
            let state =
              State(
                ..state,
                consumers: deque.push_back(state.consumers, #(
                  demand_left,
                  consumer,
                )),
              )
            gen_server.continue(state)
          }
        }
      }

      DoPull(demand) -> {
        let #(events, new_state) = pull(state.state, demand)
        let buffer = buffer.store(state.buffer, events)
        let consumers = case deque.pop_front(state.consumers) {
          Ok(#(#(demand_left, consumer), consumers)) -> {
            gen_server.cast(self, EmitEvents(demand_left, consumer))
            consumers
          }
          Error(_) -> state.consumers
        }
        let state =
          State(state: new_state, buffer: buffer, consumers: consumers)
        gen_server.continue(state)
      }
    }
  }
}

pub fn send_demand(pull: Pull(a), subject: Subject(List(a)), demand: Int) {
  gen_server.cast(pull.server, EmitEvents(demand, subject))
}
