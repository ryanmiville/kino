// import gleam/bool
// import gleam/erlang/process
// import gleam/io
// import gleam/list
// import kino/stream

// pub fn main() {
// let assert Ok(res) =
//   stream.unfold(from: 1, with: handle_demand)
//   |> stream.fold_chunks(from: "done!", with: handle_events, max: 1000)
// // |> stream.to_list

// io.println("done!")
// io.debug(res)

//   let assert Ok(list) =
//     [1, 2, 3, 4, 5]
//     |> stream.from_list
//     |> stream.fold_chunks(from: "done!", with: handle_events, max: 1000)
//   io.debug(list)
// }

// fn handle_demand(counter: Int, demand: Int) {
//   use <- bool.guard(counter > 20, stream.Done)
//   let mult = { { demand / 10 } + 1 } * 10
//   let events = list.range(counter, counter + mult - 1)
//   stream.Next(events, counter + mult)
// }

// fn handle_events(state, message: List(Int)) {
//   io.println("received events:")
//   case message {
//     [head, ..] if head > 100 -> {
//       io.println("should complete")
//       stream.Complete
//     }
//     _ -> {
//       io.debug(message)
//       process.sleep(500)
//       stream.Consume(state)
//     }
//   }
// }
