import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Subject}
import gleam/result
import kino/internal/gen_server

pub opaque type ActorRef(message) {
  ActorRef(ref: gen_server.GenServer(message, Behavior(message)))
}

pub fn send(actor: ActorRef(message), message: message) -> Nil {
  gen_server.cast(actor.ref, message)
}

pub fn call(
  actor: ActorRef(request),
  make_request: fn(Subject(response)) -> request,
  within timeout: Int,
) -> response {
  let assert Ok(resp) = try_call(actor, make_request, timeout)
  resp
}

pub fn try_call(
  actor: ActorRef(request),
  make_request: fn(Subject(response)) -> request,
  within timeout: Int,
) -> Result(response, process.CallError(response)) {
  let reply_subject = process.new_subject()

  // Monitor the callee process so we can tell if it goes down (meaning we
  // won't get a reply)
  let owner = gen_server.owner(actor.ref)
  let monitor = process.monitor_process(owner)

  // Send the request to the process over the channel
  send(actor, make_request(reply_subject))

  // Await a reply or handle failure modes (timeout, process down, etc)
  let result =
    process.new_selector()
    |> process.selecting(reply_subject, Ok)
    |> process.selecting_process_down(monitor, fn(down: process.ProcessDown) {
      Error(process.CalleeDown(reason: down.reason))
    })
    |> process.select(timeout)

  // Demonitor the process and close the channels as we're done
  process.demonitor_process(monitor)

  // Prepare an appropriate error (if present) for the caller
  case result {
    Error(Nil) -> Error(process.CallTimeout)
    Ok(res) -> res
  }
}

pub fn call_forever(
  actor: ActorRef(request),
  make_request: fn(Subject(response)) -> request,
) -> response {
  let assert Ok(resp) = try_call_forever(actor, make_request)
  resp
}

pub fn try_call_forever(
  actor: ActorRef(request),
  make_request: fn(Subject(response)) -> request,
) -> Result(response, process.CallError(c)) {
  let reply_subject = process.new_subject()

  // Monitor the callee process so we can tell if it goes down (meaning we
  // won't get a reply)
  let owner = gen_server.owner(actor.ref)
  let monitor = process.monitor_process(owner)

  // Send the request to the process over the channel
  send(actor, make_request(reply_subject))

  // Await a reply or handle failure modes (timeout, process down, etc)
  let result =
    process.new_selector()
    |> process.selecting(reply_subject, Ok)
    |> process.selecting_process_down(monitor, fn(down) {
      Error(process.CalleeDown(reason: down.reason))
    })
    |> process.select_forever

  // Demonitor the process and close the channels as we're done
  process.demonitor_process(monitor)

  result
}

pub opaque type Context(message) {
  Context(self: ActorRef(message))
}

pub fn self(context: Context(message)) -> ActorRef(message) {
  context.self
}

pub opaque type Behavior(message) {
  Receive(on_receive: fn(Context(message), message) -> Behavior(message))
  Init(on_init: fn(Context(message)) -> Behavior(message))
  Continue
  Stop
}

pub const init = Init

pub const receive = Receive

pub const continue: Behavior(message) = Continue

pub const stopped: Behavior(message) = Stop

pub fn start_link(
  behavior: Behavior(message),
) -> Result(ActorRef(message), Dynamic) {
  let spec = new_spec(behavior)
  let ref = gen_server.start_link(spec, Nil)
  result.map(ref, ActorRef)
}

type State(message) {
  State(context: Context(message), behavior: Behavior(message))
}

fn new_spec(
  behavior: Behavior(message),
) -> gen_server.Spec(init_args, message, Behavior(message), State(message)) {
  gen_server.Spec(
    init: fn(_) {
      case behavior {
        Init(on_init) -> {
          let context = new_context()
          let next = on_init(context)
          let state = State(context, next)
          Ok(state)
        }
        _ -> {
          let context = new_context()
          let state = State(context, behavior)
          Ok(state)
        }
      }
    },
    handle_call:,
    handle_cast:,
    terminate:,
  )
}

fn new_context() -> Context(message) {
  Context(ActorRef(gen_server.self()))
}

fn handle_call(
  _message,
  _from,
  state: state,
) -> gen_server.Response(response, state) {
  gen_server.Noreply(state)
}

fn terminate(_reason, _state) -> Dynamic {
  dynamic.from(Nil)
}

fn handle_cast(message: message, state: State(message)) {
  let State(context, behavior) = state
  case behavior {
    Receive(on_receive) -> {
      case on_receive(context, message) {
        Continue -> gen_server.Noreply(state)
        next -> gen_server.Noreply(State(context, next))
      }
    }
    Init(on_init) -> {
      let next = on_init(context)
      let state = State(context, next)
      gen_server.Noreply(state)
    }
    Continue -> gen_server.Noreply(state)
    Stop -> gen_server.Stop(process.Normal, state)
  }
}
