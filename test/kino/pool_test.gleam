import gleam/erlang/process
import gleam/list
import gleeunit/should
import kino/internal/atomic
import kino/pool

pub fn pool_test() {
  let completed = atomic.new()

  let pool = pool.new(10)
  {
    use _ <- list.each(list.repeat("", 100))
    pool.spawn(pool, fn() {
      process.sleep(1)
      atomic.add(completed, 1)
    })
  }

  pool.wait_forever(pool)
  atomic.get(completed)
  |> should.equal(100)
}
