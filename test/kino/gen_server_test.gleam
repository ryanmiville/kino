import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type Pid}
import gleam/otp/static_supervisor as sup
import gleam/otp/system
import gleam/result
import gleeunit/should
import kino/gen_server.{type GenServer}

pub fn get_state_test() {
  let assert Ok(server) =
    gen_server.new(gen_server.Ready, fn(_, _, state) {
      gen_server.continue(state)
    })
    |> gen_server.start_link("Test state")

  get_server_state(server)
  |> should.equal(dynamic.from("Test state"))
}

@external(erlang, "sys", "get_status")
fn get_status(a: Pid) -> Dynamic

pub fn get_status_test() {
  let assert Ok(server) =
    gen_server.new(gen_server.Ready, fn(_, _, state) {
      gen_server.continue(state)
    })
    |> gen_server.start_link("Test state")

  let assert Ok(pid) = gen_server.owner(server)
  get_status(pid)
  // TODO: assert something about the response
}

pub fn failed_init_test() {
  gen_server.new(
    fn(_) { gen_server.Failed(dynamic.from("not enough wiggles")) },
    fn(_, _, state) { gen_server.continue(state) },
  )
  |> gen_server.start_link("Test state")
  |> result.is_error
  |> should.be_true
}

pub fn suspend_resume_test() {
  let assert Ok(server) =
    gen_server.new(gen_server.Ready, fn(_, _, state) {
      gen_server.continue(state + 1)
    })
    |> gen_server.start_link(0)
  // Suspend process
  let assert Ok(pid) = gen_server.owner(server)
  system.suspend(pid)
  |> should.equal(Nil)

  // This normal message will not be handled yet so the state remains 0
  gen_server.cast(server, "hi")

  // System messages are still handled
  get_server_state(server)
  |> should.equal(dynamic.from(0))

  // Resume process
  system.resume(pid)
  |> should.equal(Nil)

  // The queued regular message has been handled so the state has incremented
  get_server_state(server)
  |> should.equal(dynamic.from(1))
}

pub fn unexpected_message_test() {
  // Quieten the logger
  logger_set_primary_config(
    atom.create_from_string("level"),
    atom.create_from_string("error"),
  )

  let assert Ok(server) =
    gen_server.new(gen_server.Ready, fn(_, req, _) { gen_server.continue(req) })
    |> gen_server.start_link("state 1")

  get_server_state(server)
  |> should.equal(dynamic.from("state 1"))

  let assert Ok(pid) = gen_server.owner(server)

  raw_send(pid, "Unexpected message 1")
  gen_server.cast(server, "state 2")
  raw_send(pid, "Unexpected message 2")

  get_server_state(server)
  |> should.equal(dynamic.from("state 2"))
}

pub fn timeout_test() {
  let assert Ok(server) =
    gen_server.new(gen_server.Timeout(_, 10), fn(_, _, state) {
      gen_server.continue(state)
    })
    |> gen_server.handle_timeout(fn(_) { gen_server.continue("TIMEOUT") })
    |> gen_server.start_link("hello")

  get_server_state(server) |> should.equal(dynamic.from("hello"))

  process.sleep(20)

  get_server_state(server) |> should.equal(dynamic.from("TIMEOUT"))

  gen_server.stop(server)
}

pub fn named_server_test() {
  let self = process.new_subject()
  let child_spec =
    gen_server.new(gen_server.Ready, fn(_, req, _) { gen_server.continue(req) })
    |> gen_server.name(atom.create_from_string("named_server_test"))
    |> gen_server.child_spec_ack("named_server_test", "state 1", self)

  let assert Ok(_) =
    sup.new(sup.OneForOne)
    |> sup.add(child_spec)
    |> sup.start_link

  let assert Ok(server) = process.receive(self, 100)

  get_server_state(server) |> should.equal(dynamic.from("state 1"))
  gen_server.cast(server, "state 2")
  get_server_state(server) |> should.equal(dynamic.from("state 2"))

  // stop server
  gen_server.stop(server)
  // wait for restart
  process.sleep(100)

  // back to initial state
  get_server_state(server) |> should.equal(dynamic.from("state 1"))
  gen_server.cast(server, "state 3")
  get_server_state(server) |> should.equal(dynamic.from("state 3"))
}

fn get_server_state(server: GenServer(a)) {
  let assert Ok(state) =
    gen_server.owner(server)
    |> result.map(system.get_state)
    |> result.try(first_element)
    |> result.try(first_element)
  state
}

fn first_element(a: Dynamic) {
  dynamic.element(1, dynamic.dynamic)(a)
  |> result.replace_error(Nil)
}

@external(erlang, "erlang", "send")
fn raw_send(a: Pid, b: anything) -> anything

@external(erlang, "logger", "set_primary_config")
fn logger_set_primary_config(a: Atom, b: Atom) -> Nil
