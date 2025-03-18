import atomic_array
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/otp/actor
import gleeunit/should
import kino/pool

fn worker(f) {
  let init = fn() { actor.Ready(Nil, process.new_selector()) }
  actor.Spec(init, 1000, fn(_, _) {
    f()
    actor.continue(Nil)
  })
}

pub fn pool_test() {
  let completed = atomic_array.new_signed(1)
  let f = fn() {
    process.sleep(1)
    let _ = atomic_array.add(completed, 0, 1)
    Nil
  }

  let pool = pool.new(10, worker(f))
  list.repeat(0, 10) |> list.each(fn(_) { pool.send(pool, "") })
  pool.stop(pool)
  process.sleep(5)
  atomic_array.get(completed, 0)
  |> should.equal(Ok(10))
}

pub fn receive_test() {
  let completed = atomic_array.new_signed(1)
  let subject = process.new_subject()
  let f = fn() {
    let assert Ok(Nil) = atomic_array.add(completed, 0, 1)
    let assert Ok(value) = atomic_array.get(completed, 0)
    process.send(subject, value)
  }
  let pool = pool.new(10, worker(f))
  list.repeat(0, 10) |> list.each(fn(_) { pool.send(pool, "") })
  pool.stop(pool)
  process.sleep(1)
  atomic_array.get(completed, 0)
  |> should.equal(Ok(10))

  list.repeat(subject, 10)
  |> list.map(process.receive_forever)
  |> list.sort(int.compare)
  |> should.equal(list.range(1, 10))
}
