import gleam/bool
import gleam/erlang/process
import gleam/int
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

pub fn app() -> kino.Spec(SayHello) {
  use _context <- kino.init()
  let assert Ok(greeter) = kino.start_link(kino.new_spec(greeter()))
  do_app(greeter)
}

fn do_app(greeter: ActorRef(Greet)) -> Behavior(SayHello) {
  use _context, SayHello(name) <- kino.receive()
  let assert Ok(bot) = kino.start_link(bot(3) |> kino.new_spec)
  kino.send(greeter, Greet(name, bot))
  kino.continue
}

pub fn main() {
  logging.configure()

  let assert Ok(app) = kino.start_link(app())
  kino.send(app, SayHello("world"))
  kino.send(app, SayHello("kino"))
  process.sleep(1000)
}
