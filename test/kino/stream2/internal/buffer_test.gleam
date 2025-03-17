import gleam/option.{None, Some}
import gleeunit/should
import kino/stream2/internal/buffer.{AtCapacity}

pub fn fifo_test() {
  let buffer = buffer.new(None)
  buffer.push(buffer, 1) |> should.be_ok
  buffer.push(buffer, 2) |> should.be_ok
  buffer.push(buffer, 3) |> should.be_ok

  buffer.pop(buffer) |> should.equal(Ok(1))
  buffer.pop(buffer) |> should.equal(Ok(2))
  buffer.pop(buffer) |> should.equal(Ok(3))
  buffer.pop(buffer) |> should.equal(Error(Nil))
}

pub fn capacity_test() {
  let buffer = buffer.new(Some(2))
  buffer.push(buffer, 1) |> should.be_ok
  buffer.push(buffer, 2) |> should.be_ok
  buffer.push(buffer, 3) |> should.equal(Error(AtCapacity))

  buffer.pop(buffer) |> should.equal(Ok(1))
  buffer.push(buffer, 3) |> should.be_ok
  buffer.pop(buffer) |> should.equal(Ok(2))
  buffer.pop(buffer) |> should.equal(Ok(3))
  buffer.pop(buffer) |> should.equal(Error(Nil))
}
