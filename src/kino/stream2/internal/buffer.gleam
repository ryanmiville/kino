import gleam/bool
import gleam/deque.{type Deque}
import gleam/erlang/process.{type Subject}
import gleam/option.{type Option, None, Some}
import gleam/otp/actor

pub opaque type Buffer(a) {
  Buffer(subject: Subject(Message(a)))
}

pub fn new(capacity: Option(Int)) -> Buffer(a) {
  let assert Ok(actor) = start(capacity)
  Buffer(actor)
}

pub fn push(buffer: Buffer(a), value: a) -> Result(Nil, AtCapacity) {
  process.call_forever(buffer.subject, Push(value, _))
}

pub fn pop(buffer: Buffer(a)) -> Result(a, Nil) {
  process.call_forever(buffer.subject, Pop)
}

pub type AtCapacity {
  AtCapacity
}

type Message(a) {
  Push(value: a, reply_to: Subject(Result(Nil, AtCapacity)))
  Pop(reply_to: Subject(Result(a, Nil)))
}

type State(a) {
  State(queue: Deque(a), count: Int, capacity: Option(Int))
}

fn start(capacity: Option(Int)) {
  let state = State(deque.new(), 0, capacity)
  actor.start(state, on_message)
}

fn on_message(msg: Message(a), state: State(a)) {
  case msg {
    Push(value, reply_to) -> {
      case do_push(state, value) {
        Ok(new_state) -> {
          process.send(reply_to, Ok(Nil))
          actor.continue(new_state)
        }
        Error(AtCapacity) -> {
          process.send(reply_to, Error(AtCapacity))
          actor.continue(state)
        }
      }
    }
    Pop(reply_to) -> {
      case do_pop(state) {
        Ok(#(value, new_state)) -> {
          process.send(reply_to, Ok(value))
          actor.continue(new_state)
        }
        Error(Nil) -> {
          process.send(reply_to, Error(Nil))
          actor.continue(state)
        }
      }
    }
  }
}

fn do_push(state: State(a), value: a) -> Result(State(a), AtCapacity) {
  use <- bool.guard(at_capacity(state), Error(AtCapacity))
  Ok(
    State(
      ..state,
      queue: deque.push_back(state.queue, value),
      count: state.count + 1,
    ),
  )
}

fn do_pop(state: State(a)) -> Result(#(a, State(a)), Nil) {
  case deque.pop_front(state.queue) {
    Error(_) -> Error(Nil)
    Ok(#(value, queue)) -> {
      Ok(#(value, State(..state, queue:, count: state.count - 1)))
    }
  }
}

fn at_capacity(state: State(a)) -> Bool {
  case state.capacity {
    None -> False
    Some(capacity) -> state.count >= capacity
  }
}
