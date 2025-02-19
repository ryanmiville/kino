// import gleam/dict.{type Dict}
// import gleam/erlang.{type Reference}
// import kino/gen_server.{type GenServer, type Next}
// import kino/gen_stage/dispatcher.{type DemandDispatcher}
// import kino/gen_stage/internal/buffer.{type Buffer}

// pub type Events(event) {
//   Events(events: List(event), counter: Int)
// }

// // -----------------------------------------------------------------------------
// // Producer
// // -----------------------------------------------------------------------------
// pub type Producer(event) {
//   Producer(server: GenServer(ProducerMessage(event)))
// }

// pub type ProducerSpec(args, event, state) {
//   ProducerSpec(
//     init: fn(args) -> InitResult(state),
//     handle_demand: fn(Int, state) -> Next(state),
//   )
// }

// pub type DemandMode {
//   Forward
//   Accumulate
// }

// pub type ProducerState(state, event) {
//   ProducerState(
//     state: state,
//     buffer: Buffer(event),
//     dispatcher: DemandDispatcher(event),
//     mode: DemandMode,
//     consumers: Dict(Reference, GenServer(event)),
//   )
// }

// pub type ProducerMessage(event) {
//   AskDemand(counter: Int, consumer: GenServer(event))
//   GetDemandMode(from: From(DemandMode))
//   Subscribe(consumer: GenServer(event))
//   EstimateBufferedCount(from: From(Int))
// }

// pub fn producer_handler(
//   self: GenServer(ProducerMessage(event)),
//   message: ProducerMessage(event),
//   state: ProducerState(state, event),
// ) -> Next(ProducerState(state, event)) {
//   case message {
//     AskDemand(counter, consumer) -> ask_demand(state, counter, consumer)
//     GetDemandMode(from) -> get_demand_mode(from, state)
//     Subscribe(consumer) -> subscribe(state, consumer)
//     EstimateBufferencedCount(from) -> estimate_buffered_count(from, state)
//   }
// }

// fn ask_demand(
//   state: ProducerState(state, event),
//   counter: Int,
//   consumer: GenServer(event),
// ) {
//   todo
// }

// fn get_demand_mode(from: From(DemandMode), state: ProducerState(state, event)) {
//   gen_server.reply(from, state.mode)
//   gen_server.continue(state)
// }

// fn subscribe(state: ProducerState(state, event), consumer: GenServer(event)) {
//   todo
// }

// fn estimate_buffered_count(from: From(Int), state: ProducerState(state, event)) {
//   todo
// }

// // -----------------------------------------------------------------------------
// // ProducerConsumer
// // -----------------------------------------------------------------------------

// pub type ProducerConsumer(event) {
//   ProducerConsumer(server: GenServer(ProducerConsumerMessage(event)))
// }

// pub type ProducerConsumerSpec(args, event, state) {
//   ProducerConsumerSpec(
//     init: fn(args) -> InitResult(state),
//     handle_events: fn(List(event), state) -> Next(state),
//   )
// }

// pub type ProducerConsumerState(state, event) {
//   ProducerConsumerState(
//     state: state,
//     buffer: Buffer(event),
//     dispatcher: DemandDispatcher(event),
//     events: Events(event),
//     producers: Dict(Reference, GenServer(ProducerMessage(event))),
//     consumers: Dict(Reference, GenServer(event)),
//   )
// }

// pub type ProducerConsumerMessage(event) {
//   SubscribeTo(producer: GenServer(ProducerMessage(event)))
//   SubscribedBy(consumer: GenServer(event))
// }

// // AskDemand(counter: Int, consumer: GenServer(event))
// // GetDemandMode(from: From(DemandMode))
// // Subscribe(consumer: GenServer(event))
// // EstimateBufferedCount(from: From(Int))

// pub fn producer_consumer_handler(
//   //todo
//   self: GenServer(ProducerConsumerMessage(event)),
//   message: ProducerConsumerMessage(event),
//   state: ProducerConsumerState(state, event),
// ) -> Next(ProducerConsumerState(state, event)) {
//   case message {
//     AskDemand(counter, consumer) -> ask_demand(state, counter, consumer)
//     GetDemandMode(from) -> get_demand_mode(from, state)
//     Subscribe(consumer) -> subscribe(state, consumer)
//     EstimateBufferencedCount(from) -> estimate_buffered_count(from, state)
//   }
// }
