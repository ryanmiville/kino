// import gleam/erlang/process
// import gleam/io
// import gleam/list
// import gleam/otp/actor
// import gleam/string
// import kino/stage
// import kino/stage/consumer
// import kino/stage/producer
// import kino/stage/producer_consumer
// import logging

// pub fn main() {
//   logging.configure()
//   logging.set_level(logging.Debug)
//   let assert Ok(producer) = producer()
//   let assert Ok(producer_consumer) = producer_consumer()
//   let assert Ok(consumer) = consumer()

//   consumer
//   |> stage.subscribe(producer_consumer.producer_subject, 4, 9)

//   producer_consumer.consumer_subject
//   |> stage.subscribe(producer, 6, 13)

//   process.sleep(5000)
// }

// fn producer() {
//   let pull = fn(state, demand) {
//     let events = list.range(state, state + demand - 1)
//     stage.Next(events, state + demand)
//   }
//   producer.new(0)
//   |> producer.pull(pull)
//   |> producer.start
// }

// fn producer_consumer() {
//   let handle_events = fn(state, events) {
//     logging.log(
//       logging.Debug,
//       "ProducerConsumer: Received events: " <> string.inspect(events),
//     )
//     // let events = list.map(events, fn(x) { x * 2 })
//     stage.Next(events, state)
//   }

//   producer_consumer.new(0)
//   |> producer_consumer.handle_events(handle_events)
//   |> producer_consumer.start
// }

// fn consumer() {
//   let handle_events = fn(state, events) {
//     io.debug(events)
//     process.sleep(500)
//     actor.continue(state)
//   }
//   consumer.new(0)
//   |> consumer.handle_events(handle_events)
//   |> consumer.start
// }
