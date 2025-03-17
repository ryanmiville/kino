import atomic_array
import gleam/erlang/process
import gleam/list
import gleeunit/should
import kino/pool

pub fn pool_test() {
  let pool = pool.new(10)
  let completed = atomic_array.new_signed(1)
  let f = fn() {
    process.sleep(1)
    let _ = atomic_array.add(completed, 0, 1)
    Nil
  }
  list.repeat(0, 10) |> list.each(fn(_) { pool.send(pool, f) })
  pool.stop(pool)
  process.sleep(2)
  atomic_array.get(completed, 0)
  |> should.equal(Ok(10))
}

pub fn receive_test() {
  let pool = pool.new(10)
  let completed = atomic_array.new_signed(1)
  let f = fn() {
    let assert Ok(Nil) = atomic_array.add(completed, 0, 1)
    let assert Ok(value) = atomic_array.get(completed, 0)
    value
  }
  let subjects = list.repeat(0, 10) |> list.map(fn(_) { pool.send(pool, f) })
  pool.stop(pool)
  process.sleep(1)
  atomic_array.get(completed, 0)
  |> should.equal(Ok(10))

  subjects
  |> list.map(process.receive_forever)
  |> should.equal(list.range(1, 10))
}
