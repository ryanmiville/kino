import gleam/bool
import gleam/deque.{type Deque}
import gleam/erlang/process.{type Subject, Normal}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor.{Spec}
import gleam/result

pub opaque type Channel(payload) {
  Channel(subject: Subject(Msg(payload)))
}

pub fn new() -> Channel(a) {
  let assert Ok(ch) = start(None) |> result.map(Channel)
  ch
}

pub fn with_capacity(capacity: Int) -> Channel(a) {
  use <- bool.lazy_guard(capacity <= 0, new)
  let assert Ok(ch) = start(Some(capacity)) |> result.map(Channel)
  ch
}

pub fn send(channel: Channel(a), value: a) {
  process.call_forever(channel.subject, Send(_, value))
}

pub fn receive(channel: Channel(a)) {
  process.call_forever(channel.subject, Receive)
}

pub fn close(channel: Channel(a)) {
  process.send(channel.subject, Close)
}

pub fn fold(channel: Channel(a), acc: acc, f: fn(acc, a) -> acc) -> acc {
  case receive(channel) {
    Ok(a) -> {
      let acc = f(acc, a)
      fold(channel, acc, f)
    }
    Error(Closed) -> acc
  }
}

pub fn try_fold(
  channel: Channel(a),
  acc: acc,
  f: fn(acc, a) -> Result(acc, e),
) -> Result(acc, e) {
  case receive(channel) {
    Ok(a) -> {
      case f(acc, a) {
        Ok(acc) -> try_fold(channel, acc, f)
        Error(e) -> Error(e)
      }
    }
    Error(Closed) -> Ok(acc)
  }
}

pub fn each(channel: Channel(a), f: fn(a) -> Nil) -> Closed {
  let _ = fold(channel, Nil, fn(_, a) { f(a) })
  Closed
}

pub fn try_each(
  channel: Channel(a),
  f: fn(a) -> Result(Nil, e),
) -> Result(Closed, e) {
  case try_fold(channel, Nil, fn(_, a) { f(a) }) {
    Ok(_) -> Ok(Closed)
    Error(error) -> Error(error)
  }
}

pub fn to_list(channel: Channel(a)) -> List(a) {
  fold(channel, [], fn(list, a) { [a, ..list] })
  |> list.reverse
}

pub type Closed {
  Closed
}

type Sender =
  Subject(Result(Nil, Closed))

type Receiver(a) =
  Subject(Result(a, Closed))

type Msg(a) {
  Send(reply_to: Sender, a)
  Receive(reply_to: Receiver(a))
  Close
  Dispatch
}

type State(a) {
  State(
    closed: Bool,
    buffer: Buffer(a),
    senders: Deque(#(Sender, a)),
    receivers: Deque(Receiver(a)),
  )
}

fn start(capacity: Option(Int)) {
  let init = fn() {
    let state =
      State(
        closed: False,
        buffer: new_buffer(capacity),
        senders: deque.new(),
        receivers: deque.new(),
      )
    actor.Ready(state, process.new_selector())
  }

  actor.start_spec(Spec(init, 1000, on_message))
}

fn on_message(msg: Msg(a), state: State(a)) {
  case msg {
    Dispatch if state.closed -> {
      close_receivers(state.receivers)
      close_senders(state.senders)
      actor.Stop(Normal)
    }

    Dispatch -> {
      dispatch(state) |> actor.continue
    }
    Send(_, _) if state.closed -> {
      panic as "sent to a closed channel"
    }
    Send(reply_to, value) -> {
      case push(state.buffer, value) {
        Ok(buffer) -> {
          process.send(reply_to, Ok(Nil))
          on_message(Dispatch, State(..state, buffer:))
        }
        Error(Nil) -> {
          let senders = deque.push_back(state.senders, #(reply_to, value))
          on_message(Dispatch, State(..state, senders:))
        }
      }
    }

    Receive(reply_to) -> {
      let receivers = deque.push_back(state.receivers, reply_to)
      on_message(Dispatch, State(..state, receivers:))
    }

    Close -> {
      on_message(Dispatch, State(..state, closed: True))
    }
  }
}

fn close_senders(senders: Deque(#(Sender, a))) -> Deque(#(Sender, a)) {
  case deque.pop_front(senders) {
    Error(_) -> senders
    Ok(#(#(sender, _), rest)) -> {
      process.send(sender, Error(Closed))
      close_senders(rest)
    }
  }
}

fn close_receivers(receivers: Deque(Receiver(a))) -> Deque(Receiver(a)) {
  case deque.pop_front(receivers) {
    Error(_) -> receivers
    Ok(#(receiver, rest)) -> {
      process.send(receiver, Error(Closed))
      close_receivers(rest)
    }
  }
}

fn dispatch(state: State(a)) -> State(a) {
  let #(senders, buffer) = dispatch_senders(state.senders, state.buffer)
  let #(receivers, buffer) = dispatch_receivers(state.receivers, buffer)
  State(..state, senders:, receivers:, buffer:)
}

fn dispatch_receivers(
  receivers: Deque(Receiver(a)),
  buffer: Buffer(a),
) -> #(Deque(Receiver(a)), Buffer(a)) {
  case deque.pop_front(receivers), pop(buffer) {
    Error(_), _ | _, Error(_) -> #(receivers, buffer)
    Ok(#(receiver, receivers)), Ok(#(value, buffer)) -> {
      process.send(receiver, Ok(value))
      dispatch_receivers(receivers, buffer)
    }
  }
}

fn dispatch_senders(
  senders: Deque(#(Sender, a)),
  buffer: Buffer(a),
) -> #(Deque(#(Sender, a)), Buffer(a)) {
  case deque.pop_front(senders) {
    Error(_) -> #(senders, buffer)
    Ok(#(#(sender, value), rest)) -> {
      case push(buffer, value) {
        Ok(buffer) -> {
          process.send(sender, Ok(Nil))
          dispatch_senders(rest, buffer)
        }
        Error(_) -> #(senders, buffer)
      }
    }
  }
}

// BUFFER --------------------------------------------------------------------------------
pub type Buffer(a) {
  Buffer(queue: Deque(a), counter: Int, capacity: Option(Int))
}

fn new_buffer(capacity: Option(Int)) -> Buffer(a) {
  Buffer(deque.new(), 0, capacity)
}

fn push(buffer: Buffer(a), value: a) -> Result(Buffer(a), Nil) {
  use <- bool.guard(at_capacity(buffer), Error(Nil))
  Ok(
    Buffer(
      ..buffer,
      queue: deque.push_back(buffer.queue, value),
      counter: buffer.counter + 1,
    ),
  )
}

fn pop(buffer: Buffer(a)) -> Result(#(a, Buffer(a)), Nil) {
  case deque.pop_front(buffer.queue) {
    Error(_) -> Error(Nil)
    Ok(#(value, queue)) -> {
      Ok(#(value, Buffer(..buffer, queue: queue, counter: buffer.counter - 1)))
    }
  }
}

fn at_capacity(buffer: Buffer(a)) -> Bool {
  case buffer.capacity {
    None -> False
    Some(capacity) -> buffer.counter >= capacity
  }
}
