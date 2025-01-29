// import gleam/erlang/process.{type Subject}
import gleeunit

// import kino.{type ActorRef, type Behavior, type Spec}

pub fn main() {
  gleeunit.main()
}
// pub fn example_test() {
//   let assert Ok(stack) = start_link()
//   kino.send(stack, Push("Joe"))
//   kino.send(stack, Push("Mike"))
//   kino.send(stack, Push("Robert"))

//   let assert Ok(Ok("Robert")) = kino.try_call(stack, Pop, 10)
//   let assert Ok(Ok("Mike")) = kino.try_call(stack, Pop, 10)
//   let assert Ok(Ok("Joe")) = kino.try_call(stack, Pop, 10)

//   // The stack is now empty, so if we pop again the actor replies with an error.
//   let assert Ok(Error(Nil)) = kino.try_call(stack, Pop, 10)
//   // Lastly, we can send a message to the actor asking it to shut down.
//   kino.send(stack, Shutdown)
// }

// pub type Message(element) {

//   Shutdown

//   Push(push: element)

//   Pop(reply_to: Subject(Result(element, Nil)))
// }

// pub fn new_stack_server() -> Spec(ActorRef(Message(element))) {
//   use _context <- kino.actor()
//   stack_server([])
// }

// fn stack_server(stack: List(element)) -> Behavior(Message(element)) {
//   use _context, message <- kino.receive()
//   case message {
//     Push(value) -> {
//       let new_stack = [value, ..stack]
//       stack_server(new_stack)
//     }

//     Pop(reply_to:) -> {
//       case stack {
//         [] -> {
//           process.send(reply_to, Error(Nil))
//           stack_server(stack)
//         }

//         [first, ..rest] -> {
//           process.send(reply_to, Ok(first))
//           stack_server(rest)
//         }
//       }
//     }

//     Shutdown -> {
//       kino.stopped
//     }
//   }
// }

// pub fn start_link() {
//   kino.start_link(new_stack_server())
// }
