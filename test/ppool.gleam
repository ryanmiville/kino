import gleam/erlang/process
import gleam/io
import logging
import ppool/ppool

pub fn main() {
  logging.configure()
  let self = process.new_subject()
  process.start(fn() { do(self) }, True)
  flush_forever(self)
}

fn do(reply_to) {
  let assert Ok(sup) = ppool.start_link()
  let assert Ok(pool) = ppool.start_pool(sup, 2)

  let _ = run(pool, reply_to)
  process.sleep(1100)
  async_queue(pool, reply_to)
  process.sleep(2100)
  let _ = sync_queue(pool, reply_to)
  process.sleep_forever()
}

fn run(pool, reply_to) {
  let delay = 1000
  let max = 10
  let assert Ok(Ok(_)) =
    ppool.run(pool:, delay:, max:, reply_to:, task: "finish the chapter!")

  let assert Ok(Ok(_)) =
    ppool.run(pool:, delay:, max:, reply_to:, task: "watch a good movie")

  let assert Ok(Error(_)) =
    ppool.run(pool:, delay:, max:, reply_to:, task: "clean up a bit")
}

fn async_queue(pool, reply_to) {
  let delay = 1000
  let max = 1
  ppool.async_queue(pool:, delay:, max:, reply_to:, task: "Pay the bills")
  ppool.async_queue(pool:, delay:, max:, reply_to:, task: "Take a shower")
  ppool.async_queue(pool:, delay:, max:, reply_to:, task: "Plant a tree")
}

fn sync_queue(pool, reply_to) {
  let delay = 2000
  let max = 1
  let assert Ok(_) =
    ppool.sync_queue(pool:, delay:, max:, reply_to:, task: "Pet a dog")

  let assert Ok(_) =
    ppool.sync_queue(pool:, delay:, max:, reply_to:, task: "Make some noise")

  let assert Ok(_) =
    ppool.sync_queue(pool:, delay:, max:, reply_to:, task: "Chase a tornado")
}

fn flush_forever(subject) {
  let msg = process.receive_forever(subject)
  io.println(">>> received: " <> msg)
  flush_forever(subject)
}
