import gleam/erlang/process
import gleam/io
import gleam/list
import gleam/otp/actor
import kino/sink
import kino/source

pub fn main() {
  let assert Ok(source) = source.new(1, handle_demand)
  let assert Ok(sink) = sink.new(Nil, handle_events)

  source.subscribe(source, sink.subject, 4)
  process.sleep(10_000)
}

fn handle_demand(counter: Int, demand: Int) {
  let mult = { { demand / 10 } + 1 } * 10
  let events = list.range(counter, counter + mult)
  source.Next(events, counter + mult)
}

fn handle_events(state, message: List(Int)) {
  io.println("received events:")
  io.debug(message)
  process.sleep(1000)
  actor.continue(state)
}
