import gleam/bool
import gleam/erlang/process.{type Subject}
import gleam/function
import gleam/int
import gleam/list
import gleam/otp/actor.{type StartError}
import logging

pub type Greet {
  Greet(whom: String, reply_to: Subject(Greeted))
}

pub type Greeted {
  Greeted(whom: String, from: Subject(Greet))
}

pub type SayHello {
  SayHello(name: String)
}

pub fn greeter() -> Result(Subject(Greet), StartError) {
  actor.start_spec(actor.Spec(
    init: greet_init,
    loop: greet_loop,
    init_timeout: 200,
  ))
}

fn greet_init() {
  let self = process.new_subject()
  let selector =
    process.new_selector()
    |> process.selecting(self, function.identity)
  actor.Ready(self, selector)
}

fn greet_loop(message: Greet, self) {
  let Greet(whom, reply_to) = message

  logging.log(logging.Info, "Hello, " <> whom <> "!")

  process.send(reply_to, Greeted(whom, self))
  actor.continue(self)
}

pub fn bot(max: Int) -> Result(Subject(Greeted), StartError) {
  actor.start_spec(actor.Spec(
    init: fn() { bot_init(max) },
    loop: bot_loop,
    init_timeout: 200,
  ))
}

type BotState {
  BotState(self: Subject(Greeted), count: Int, max: Int)
}

fn bot_init(max: Int) {
  let self = process.new_subject()
  let selector =
    process.new_selector()
    |> process.selecting(self, function.identity)
  actor.Ready(BotState(self, 0, max), selector)
}

fn bot_loop(message: Greeted, state: BotState) {
  let Greeted(whom, from) = message

  let count = state.count + 1
  logging.log(
    logging.Info,
    "Greeting " <> int.to_string(count) <> " for " <> whom,
  )

  use <- bool.guard(count == state.max, actor.Stop(process.Normal))
  process.send(from, Greet(whom, state.self))
  actor.continue(BotState(state.self, count, state.max))
}

pub fn app() -> Result(Subject(SayHello), StartError) {
  actor.start_spec(actor.Spec(init: app_init, loop: app_loop, init_timeout: 200))
}

type AppState {
  AppState(self: Subject(SayHello), greeter: Subject(Greet))
}

fn app_init() {
  let self = process.new_subject()
  let selector =
    process.new_selector()
    |> process.selecting(self, function.identity)

  let assert Ok(greeter) = greeter()
  actor.Ready(AppState(self, greeter), selector)
}

fn app_loop(message: SayHello, state: AppState) {
  let SayHello(name) = message

  let assert Ok(bot) = bot(3)

  process.send(state.greeter, Greet(name, bot))
  actor.continue(state)
}

pub fn main() {
  logging.configure()
  let assert Ok(app) = app()
  list.range(1, 10)
  |> list.each(fn(i) { process.send(app, SayHello(int.to_string(i))) })
  process.sleep(1000)
  process.kill(process.subject_owner(app))
}
