import gleam/bool
import gleam/erlang/process
import gleam/int
import gleam/list
import kino.{type ActorRef, type Behavior}
import logging

pub type Greet {
  Greet(whom: String, reply_to: ActorRef(Greeted))
}

pub type Greeted {
  Greeted(whom: String, from: ActorRef(Greet))
}

pub type SayHello {
  SayHello(name: String)
}

pub fn greeter() -> Behavior(Greet) {
  use context, Greet(whom, reply_to) <- kino.receive()
  logging.log(logging.Info, "Hello, " <> whom <> "!")
  kino.send(reply_to, Greeted(whom, kino.self(context)))
  kino.continue
}

pub fn bot(max: Int) -> Behavior(Greeted) {
  do_bot(0, max)
}

fn do_bot(count: Int, max: Int) -> Behavior(Greeted) {
  use context, Greeted(whom, from) <- kino.receive()

  let count = count + 1
  logging.log(
    logging.Info,
    "Greeting " <> int.to_string(count) <> " for " <> whom,
  )

  use <- bool.guard(count == max, kino.stopped)

  kino.send(from, Greet(whom, kino.self(context)))
  do_bot(count, max)
}

pub fn app() -> Behavior(SayHello) {
  use _context <- kino.init()
  let greeter = kino.spawn_link(greeter(), "greeter")
  do_app(greeter)
}

fn do_app(greeter: ActorRef(Greet)) -> Behavior(SayHello) {
  use _context, SayHello(name) <- kino.receive()
  let bot = kino.spawn_link(bot(3), name)
  kino.send(greeter, Greet(name, bot))
  kino.continue
}

pub fn main() {
  logging.configure()
  // logging.set_level(logging.Critical)

  let app = kino.spawn_link(app(), "app")
  list.range(1, 100)
  |> list.each(fn(i) { kino.send(app, SayHello(int.to_string(i))) })
  // kino.send(app, SayHello("world"))
  // kino.send(app, SayHello("kino"))
  process.sleep(1000)
}
