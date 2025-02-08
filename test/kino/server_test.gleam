import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type Pid}
import gleam/otp/static_supervisor as sup
import gleam/otp/system
import gleam/result
import gleeunit/should
import kino/server.{type From, type InitResult, type Next, type Server}
import logging

pub fn example_test() {
  let assert Ok(srv) = start_link([], atom.create_from_string("example_test"))
  server.cast(srv, Push("Joe"))
  server.cast(srv, Push("Mike"))
  server.cast(srv, Push("Robert"))

  server.call(srv, Pop, 10) |> should.equal(Ok("Robert"))
  server.call(srv, Pop, 10) |> should.equal(Ok("Mike"))
  server.call(srv, Pop, 10) |> should.equal(Ok("Joe"))

  // The stack is now empty, so if we pop again the actor replies with an error.
  server.call(srv, Pop, 10) |> should.equal(Error(Nil))
  server.stop(srv)
}

pub fn unhandled_message_type_test() {
  logging.set_level(logging.Error)
  let assert Ok(srv) =
    start_link([], atom.create_from_string("unhandled_message_type_test"))
  let assert Ok(pid) = server.owner(srv)
  raw_send(pid, "hello")
  server.cast(srv, Push("Joe"))
  server.call(srv, Pop, 10) |> should.equal(Ok("Joe"))
  server.stop(srv)
  logging.set_level(logging.Info)
}

pub fn restart_test() {
  let self = process.new_subject()
  let assert Ok(_) =
    sup.new(sup.OneForOne)
    |> sup.add(
      sup.worker_child("stack-worker", fn() {
        start_link([], atom.create_from_string("restart_test"))
        |> server.to_supervise_result_ack(self)
      }),
    )
    |> sup.start_link()

  let assert Ok(srv) = process.receive(self, 100)

  server.cast(srv, Push("Joe"))
  server.cast(srv, Push("Mike"))
  server.call(srv, Pop, 10) |> should.equal(Ok("Mike"))

  // stop server
  server.stop(srv)

  // wait for restart
  process.sleep(100)

  server.cast(srv, Push("Robert"))
  server.call(srv, Pop, 10) |> should.equal(Ok("Robert"))
  // restart lost Joe
  server.call(srv, Pop, 10) |> should.equal(Error(Nil))
}

pub fn timeout_test() {
  let assert Ok(srv) =
    server.new(fn(args) { server.Timeout(args, 10) }, fn(_, _, state) {
      server.continue(state)
    })
    |> server.handle_timeout(fn(_) { server.continue("TIMEOUT") })
    |> server.start_link("hello")

  let assert Ok(pid) = server.owner(srv)

  get_state(pid) |> should.equal(dynamic.from("hello"))

  process.sleep(10)

  get_state(pid) |> should.equal(dynamic.from("TIMEOUT"))

  server.stop(srv)
}

pub type Request(element) {
  Push(element)
  Pop(From(Result(element, Nil)))
}

pub fn start_link(
  stack: List(element),
  name: Atom,
) -> Result(Server(Request(element)), Dynamic) {
  server.new(init, handler)
  |> server.name(name)
  |> server.start_link(stack)
}

fn init(stack: List(element)) -> InitResult(List(element)) {
  server.Ready(stack)
}

fn handler(
  _self: Server(request),
  request: Request(element),
  state: List(element),
) -> Next(List(element)) {
  case request {
    Push(element) -> server.continue([element, ..state])

    Pop(from) ->
      case state {
        [] -> {
          server.reply(from, Error(Nil))
          server.continue(state)
        }
        [first, ..rest] -> {
          server.reply(from, Ok(first))
          server.continue(rest)
        }
      }
  }
}

@external(erlang, "erlang", "send")
fn raw_send(a: Pid, b: anything) -> anything

fn get_state(pid: Pid) {
  let assert Ok(state) =
    system.get_state(pid)
    |> dynamic.element(1, dynamic.dynamic)
    |> result.try(dynamic.element(1, dynamic.dynamic))
  state
}
