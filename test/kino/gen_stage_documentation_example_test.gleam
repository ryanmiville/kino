// import gleam/erlang/process
// import gleam/int
// import gleam/io
// import gleam/list
// import kino/gen_stage

// pub fn example_test() {
//   let assert Ok(a) = gen_stage.start_link(producer(), 0)
//   let assert Ok(b) = gen_stage.start_link(producer_consumer(), 2)
//   let assert Ok(c) = gen_stage.start_link(consumer(), Nil)

//   gen_stage.sync_subscribe(c, to: b)
//   gen_stage.sync_subscribe(b, to: a)

//   let done = process.new_subject()
//   process.start(
//     fn() {
//       process.sleep(5000)
//       gen_stage.stop(c)
//       process.send(done, Nil)
//     },
//     False,
//   )

//   process.receive_forever(done)
// }

// fn producer() {
//   gen_stage.new_producer(gen_stage.ready, producer_handle_demand)
// }

// fn producer_handle_demand(demand: Int, counter: Int) {
//   use demand <- gen_stage.valid_demand(demand)
//   let events = list.range(counter, counter + demand - 1)
//   gen_stage.reply_demand(events, counter + demand)
// }

// fn producer_consumer() {
//   gen_stage.new_producer_consumer(
//     gen_stage.ready,
//     producer_consumer_handle_events,
//   )
// }

// fn producer_consumer_handle_events(events: List(Int), _from, multiplier: Int) {
//   let events = list.map(events, int.multiply(_, multiplier))
//   gen_stage.reply_events(events, multiplier)
// }

// fn consumer() {
//   gen_stage.new_consumer(fn(_) { gen_stage.ready(Nil) }, consumer_handle_events)
// }

// fn consumer_handle_events(events: List(Int), _from, state) {
//   process.sleep(1000)
//   io.debug(events)
//   gen_stage.drain(state)
// }
