import gleam/erlang/process
import gleeunit/should
import kino/channel

pub fn send_receive_test() {
  let channel = channel.new()
  let sender = fn() { channel.send(channel, "Hello") }
  process.start(sender, True)

  channel.receive(channel)
  |> should.equal(Ok("Hello"))
}

pub fn close_test() {
  let channel = channel.new()
  let closer = fn() { channel.close(channel) }
  process.start(closer, True)

  channel.receive(channel)
  |> should.equal(Error(channel.Closed))
}

pub fn unbuffered_test() {
  let channel = channel.new()

  let first = fn() {
    let _ = channel.send(channel, 1)
    let _ = channel.send(channel, 1)
  }
  process.start(first, True)

  process.sleep(10)
  let second = fn() {
    let _ = channel.send(channel, 2)
  }
  process.start(second, True)

  channel.receive(channel)
  |> should.equal(Ok(1))
  channel.receive(channel)
  |> should.equal(Ok(1))
  channel.receive(channel)
  |> should.equal(Ok(2))
}

pub fn buffered_test() {
  let channel = channel.with_capacity(1)

  let first = fn() {
    let _ = channel.send(channel, 1)
    let _ = channel.send(channel, 1)
  }
  process.start(first, True)

  process.sleep(10)
  let second = fn() {
    let _ = channel.send(channel, 2)
  }
  process.start(second, True)

  channel.receive(channel)
  |> should.equal(Ok(1))
  channel.receive(channel)
  |> should.equal(Ok(2))
  channel.receive(channel)
  |> should.equal(Ok(1))
}
// pub fn fold_test() {
//   let channel = channel.new()
//   let f = fn() {
//     let _ = channel.send(channel, 1)
//     let _ = channel.send(channel, 2)
//     let _ = channel.send(channel, 3)
//     channel.close(channel)
//   }
//   process.start(f, True)

//   channel.fold(channel, 0, fn(acc, value) { acc + value })
//   |> should.equal(6)
// }
