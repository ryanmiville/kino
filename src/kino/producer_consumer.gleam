import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type ProcessMonitor, type Selector, type Subject}
import gleam/function
import gleam/otp/actor
import gleam/result
import gleam/set.{type Set}
import kino/gen_stage.{
  type ConsumerMessage, type DemandDispatcher, type ProducerConsumerMessage,
  type ProducerMessage, ConsumerMessage, ProducerMessage,
}
import kino/gen_stage/internal/buffer.{type Buffer}

pub type ProducerConsumer(in, out) {
  ProducerConsumer(
    subject: Subject(ProducerConsumerMessage(in, out)),
    consumer_subject: Subject(ConsumerMessage(in)),
    producer_subject: Subject(ProducerMessage(out)),
  )
}

pub type State(state, in, out) {
  State(
    self: Subject(ProducerConsumerMessage(in, out)),
    consumer_self: Subject(ConsumerMessage(in)),
    producer_self: Subject(ProducerMessage(out)),
    selector: Selector(ProducerConsumerMessage(in, out)),
    state: state,
    buffer: Buffer(out),
    dispatcher: DemandDispatcher(out),
    producers: Set(Subject(ProducerMessage(in))),
    consumers: Set(Subject(ConsumerMessage(out))),
    producer_monitors: Dict(
      Subject(gen_stage.ProducerMessage(in)),
      ProcessMonitor,
    ),
    consumer_monitors: Dict(
      Subject(gen_stage.ConsumerMessage(out)),
      ProcessMonitor,
    ),
    handle_events: fn(state, List(in)) -> gen_stage.Produce(state, out),
  )
}

pub fn new(
  state: state,
  handle_events: fn(state, List(in)) -> gen_stage.Produce(state, out),
) -> Result(ProducerConsumer(in, out), Dynamic) {
  let ack = process.new_subject()
  actor.start_spec(actor.Spec(
    init: fn() {
      let self = process.new_subject()
      let consumer_self = process.new_subject()
      let producer_self = process.new_subject()

      let ps =
        process.new_selector()
        |> process.map_selector(gen_stage.ProducerMessage)
      let cs =
        process.new_selector()
        |> process.map_selector(gen_stage.ConsumerMessage)

      let selector =
        process.new_selector()
        |> process.selecting(self, function.identity)
        |> process.merge_selector(ps)
        |> process.merge_selector(cs)

      process.send(ack, #(self, consumer_self, producer_self))
      let state =
        State(
          self:,
          consumer_self:,
          producer_self:,
          selector:,
          state:,
          buffer: buffer.new(),
          dispatcher: gen_stage.new_dispatcher(),
          consumers: set.new(),
          producers: set.new(),
          consumer_monitors: dict.new(),
          producer_monitors: dict.new(),
          handle_events:,
        )
      actor.Ready(state, selector)
    },
    loop: handler,
    init_timeout: 5000,
  ))
  |> result.map(fn(_) {
    let #(self, consumer_self, producer_self) = process.receive_forever(ack)
    ProducerConsumer(self, consumer_self, producer_self)
  })
  |> result.map_error(dynamic.from)
}

pub fn handler(
  message: ProducerConsumerMessage(in, out),
  state: State(state, in, out),
) {
  case message {
    ProducerMessage(message) -> producer_handler(message, state)
    ConsumerMessage(message) -> consumer_handler(message, state)
  }
}

fn producer_handler(message: ProducerMessage(out), state: State(state, in, out)) {
  case message {
    gen_stage.Subscribe(consumer, demand) -> {
      todo
    }
    gen_stage.Ask(demand:, consumer:) -> {
      todo
    }
    gen_stage.Unsubscribe(consumer) -> {
      todo
    }
    gen_stage.ConsumerDown(consumer) -> {
      todo
    }
  }
}

fn consumer_handler(message: ConsumerMessage(in), state: State(state, in, out)) {
  case message {
    gen_stage.ConsumerSubscribe(source, min, max) -> {
      todo
    }
    gen_stage.NewEvents(events:, from:) -> {
      todo
    }
    gen_stage.ConsumerUnsubscribe(source) -> {
      todo
    }
    gen_stage.ProducerDown(source) -> {
      todo
    }
  }
}
