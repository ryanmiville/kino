import gleam/erlang/process
import gleam/otp/actor
import gleam/otp/static_supervisor as sup
import gleam/otp/task
import gleam/result
import gleeunit
import gleeunit/should
import kino
import logging

pub fn main() {
  logging.configure()
  gleeunit.main()
}

type TestMsg {
  Send(reply_to: process.Subject(String))
  Wait(value: Int, reply_to: process.Subject(Int))
  Kill
  Shutdown
}

fn default_handle(msg: TestMsg, _state: Nil) {
  case msg {
    Send(reply_to:) -> {
      logging.log(logging.Info, "received Send")
      process.send(reply_to, "Sent")
      actor.continue(Nil)
    }
    Wait(value:, reply_to:) -> {
      logging.log(logging.Info, "received Wait")
      process.sleep(value)
      process.send(reply_to, value)
      actor.continue(Nil)
    }

    Kill -> {
      logging.log(logging.Info, "received Kill")
      panic as "crashed in handle"
    }

    Shutdown -> {
      logging.log(logging.Info, "received Shutdown")
      actor.Stop(process.Normal)
    }
  }
}

// fn default_spec() {
//   actor.Spec(
//     init_timeout: 1000,
//     init: fn() { actor.Ready(state: Nil, selector: process.new_selector()) },
//     loop: default_handle,
//   )
// }

// pub fn send_test() {
//   let assert Ok(ref) = kino.start(Nil, default_handle)
//   let self_subject = process.new_subject()

//   kino.send(ref, Send(self_subject))
//   kino.send(ref, Send(self_subject))

//   process.receive(self_subject, 1000)
//   |> should.equal(Ok("Sent"))

//   process.receive(self_subject, 1000)
//   |> should.equal(Ok("Sent"))

//   process.receive(self_subject, 1000)
//   |> should.equal(Error(Nil))
// }

// pub fn call_test() {
//   let assert Ok(ref) = kino.start(Nil, default_handle)

//   kino.call(ref, Wait(100, _), 500)
//   |> should.equal(100)

//   kino.call(ref, Wait(50, _), 500)
//   |> should.equal(50)
// }

// pub fn try_call_test() {
//   let assert Ok(ref) = kino.start(Nil, default_handle)

//   // Send a wait message that takes a long time
//   let handle = task.async(fn() { kino.call(ref, Wait(1000, _), 1250) })

//   // Wait to let the other process start
//   process.sleep(100)

//   kino.try_call(ref, Wait(1, _), 200)
//   |> should.be_error

//   // Wait for the other process to finish
//   task.try_await(handle, 1000)
//   |> should.equal(Ok(1000))
// }

pub fn restart_test() {
  // let self = process.new_subject()
  // process.start(
  //   fn() {
  //     let assert Ok(ref) = kino.start(Nil, default_handle)
  //     process.send(self, ref)
  //     process.sleep_forever()
  //   },
  //   False,
  // )

  let assert Ok(ref) = kino.start(Nil, default_handle)
  // let assert Ok(ref) = kino.start(Nil, default_handle)

  kino.try_call(ref, Wait(50, _), 5000)
  |> should.equal(Ok(50))

  kino.send(ref, Kill)

  // let assert Ok(ref) = process.receive(self, 5000)
  // process.is_alive(ref.subject |> process.subject_owner)
  // |> should.equal(True)

  process.sleep(1000)
  // process.is_alive(ref.subject |> process.subject_owner)
  // |> should.equal(True)
  kino.call(ref, Wait(100, _), 5000)
  |> should.equal(100)
}

// pub fn normal_test() {
//   let parent = process.new_subject()
//   let assert Ok(_supervisor) =
//     sup.new(sup.OneForOne)
//     |> sup.add(sup.worker_child("worker", worker_child(parent)))
//     |> sup.start_link

//   let assert Ok(subject) = process.receive(parent, 1000)

//   actor.call(subject, Wait(1000, _), 2000)
//   |> should.equal(1000)

//   process.kill(process.subject_owner(subject))

//   let assert Ok(subject) = process.receive(parent, 5000)
//   process.try_call(subject, Wait(100, _), 1000)
//   |> should.equal(Ok(100))
// }

fn worker_child(parent) {
  fn() {
    use subject <- result.map(actor.start(Nil, default_handle))
    process.send(parent, subject)
    process.subject_owner(subject)
  }
}
