import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom.{type Atom}
import gleam/option.{type Option}
import kino/gen_server.{type GenServer}
import kino/gen_stage/internal/buffer.{type Buffer}

pub type InitResult(state) =
  gen_server.InitResult(state)

pub type Next(state) =
  gen_server.Next(state)

pub type From(reply) =
  gen_server.From(reply)

type Kind {
  Producer
  ProducerConsumer
  Consumer
}

type State(event, state) {
  State(kind: Kind, state: state, buffer: Buffer(event))
}

pub opaque type GenStage(event) {
  GenStage(server: GenServer(event))
}

type DemandMode {
  Forward
  Accumulate
}

type Message(event, state) {
  AskDemand(demand: Int)
  GetDemandMode(from: From(DemandMode))
  SetDemandMode(mode: DemandMode)
  Events(events: List(event), from: From(Bool))
  SyncSubscribe(to: GenStage(event), from: From(Bool))
  AsyncSubscribe(to: GenStage(event))
  EstimateBufferCount(from: From(Int))
}

pub type Spec(args, event, state) {
  Spec(
    server_spec: gen_server.Spec(args, event, state),
    handle_demand: fn(Int, state) -> Next(state),
    handle_events: fn(List(event), state) -> Next(state),
  )
}

pub fn ready(state) -> InitResult(state) {
  gen_server.Ready(state)
}

pub fn timeout(state, timeout) -> InitResult(state) {
  gen_server.Timeout(state, timeout)
}

pub fn failed(reason) -> InitResult(state) {
  gen_server.Failed(reason)
}

pub fn start_link(
  spec: Spec(args, event, state),
  args: args,
) -> Result(GenStage(event), Dynamic) {
  todo
}

pub fn new_producer(
  init init: fn(args) -> InitResult(state),
  handle_demand handle_demand: fn(Int, state) -> Next(state),
) -> Spec(args, event, state) {
  todo
}

pub fn new_producer_consumer(
  init init: fn(args) -> InitResult(state),
  handle_events handle_events: fn(List(event), From(reply), state) ->
    Next(state),
) -> Spec(args, event, state) {
  todo
}

pub fn new_consumer(
  init init: fn(args) -> InitResult(state),
  handle_events handle_events: fn(List(event), From(reply), state) ->
    Next(state),
) -> Spec(args, event, state) {
  todo
}

pub fn reply_demand(events, state) -> Next(state) {
  todo
}
