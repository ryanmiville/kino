import gleam/bool
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type ProcessMonitor, type Selector, type Subject}
import gleam/function
import gleam/io
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/set.{type Set}
import kino/gen_stage/internal/buffer.{type Buffer}
import kino/source.{
  type DemandDispatcher, type FlowMessage, type SinkMessage, type SourceMessage,
  ConsumerMessage, ProducerMessage,
}

pub type Flow(in, out) {
  Flow(
    subject: Subject(FlowMessage(in, out)),
    consumer_subject: Subject(SinkMessage(in)),
    producer_subject: Subject(SourceMessage(out)),
  )
}

pub type State(state, in, out) {
  State(
    self: Subject(FlowMessage(in, out)),
    consumer_self: Subject(SinkMessage(in)),
    producer_self: Subject(SourceMessage(out)),
    selector: Selector(FlowMessage(in, out)),
    state: state,
    buffer: Buffer(out),
    dispatcher: DemandDispatcher(out),
    producers: Set(Subject(SourceMessage(in))),
    consumers: Set(Subject(SinkMessage(out))),
    producer_monitors: Dict(Subject(source.Message(in)), ProcessMonitor),
    consumer_monitors: Dict(Subject(source.SinkMessage(out)), ProcessMonitor),
    handle_events: fn(state, List(in)) -> source.Produce(state, out),
  )
}

pub fn new(
  state: state,
  handle_events: fn(state, List(in)) -> source.Produce(state, out),
) -> Result(Flow(in, out), Dynamic) {
  let ack = process.new_subject()
  actor.start_spec(actor.Spec(
    init: fn() {
      let self = process.new_subject()
      let consumer_self = process.new_subject()
      let producer_self = process.new_subject()

      let ps =
        process.new_selector() |> process.map_selector(source.ProducerMessage)
      let cs =
        process.new_selector() |> process.map_selector(source.ConsumerMessage)

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
          dispatcher: source.new_dispatcher(),
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
    Flow(self, consumer_self, producer_self)
  })
  |> result.map_error(dynamic.from)
}

pub fn handler(message: FlowMessage(in, out), state: State(state, in, out)) {
  case message {
    ProducerMessage(message) -> producer_handler(message, state)
    ConsumerMessage(message) -> consumer_handler(message, state)
  }
}

fn producer_handler(message: SourceMessage(out), state: State(state, in, out)) {
  case message {
    source.Subscribe(consumer, demand) -> {
      todo
      // let consumers = set.insert(state.consumers, consumer)
      // let mon = process.monitor_process(process.subject_owner(consumer))
      // let selector =
      //   process.new_selector()
      //   |> process.selecting_process_down(mon, fn(_) {
      //     source.ConsumerDown(consumer)
      //   })
      //   |> process.merge_selector(state.selector)
      // process.send(state.self, Ask(demand, consumer))
      // let dispatcher = subscribe_dispatcher(state.dispatcher, consumer)
      // let monitors = state.monitors |> dict.insert(consumer, mon)
      // let state = State(..state, selector:, consumers:, dispatcher:, monitors:)
      // actor.continue(state) |> actor.with_selector(selector)
    }
    source.Ask(demand:, consumer:) -> {
      todo
      // ask_demand(demand, consumer, state)
    }
    source.Unsubscribe(consumer) -> {
      todo
      // let consumers = set.delete(state.consumers, consumer)
      // let monitors = case dict.get(state.monitors, consumer) {
      //   Ok(mon) -> {
      //     process.demonitor_process(mon)
      //     dict.delete(state.monitors, consumer)
      //   }
      //   _ -> state.monitors
      // }
      // let dispatcher = cancel(state.dispatcher, consumer)
      // let state = State(..state, consumers:, dispatcher:, monitors:)
      // actor.continue(state)
    }
    source.ConsumerDown(consumer) -> {
      todo
      // io.println("consumer down")
      // let consumers = set.delete(state.consumers, consumer)
      // let monitors = dict.delete(state.monitors, consumer)
      // let dispatcher = cancel(state.dispatcher, consumer)
      // let state = State(..state, consumers:, dispatcher:, monitors:)
      // actor.continue(state)
    }
  }
}

fn consumer_handler(message: SinkMessage(in), state: State(state, in, out)) {
  case message {
    source.SinkSubscribe(source, min, max) -> {
      todo
      // let producers =
      //   dict.insert(state.producers, source, Demand(current: max, min:, max:))
      // let mon = process.monitor_process(process.subject_owner(source))
      // let selector =
      //   process.new_selector()
      //   |> process.selecting_process_down(mon, fn(_) { ProducerDown(source) })
      //   |> process.merge_selector(state.selector)

      // let monitors = state.monitors |> dict.insert(source, mon)
      // let state = State(..state, selector:, producers:, monitors:)
      // process.send(source, source.Subscribe(state.self, max))
      // actor.continue(state) |> actor.with_selector(selector)
    }
    source.NewEvents(events:, from:) -> {
      todo
      // case dict.get(state.producers, from) {
      //   Ok(demand) -> {
      //     let #(current, batches) = split_batches(events, demand)
      //     let demand = Demand(..demand, current:)
      //     let producers = dict.insert(state.producers, from, demand)
      //     let state = State(..state, producers:)
      //     dispatch(state, batches, from)
      //   }
      //   Error(_) -> actor.continue(state)
      // }
    }
    source.SinkUnsubscribe(source) -> {
      todo
      // io.println("unsub producer")
      // let producers = dict.delete(state.producers, source)
      // let monitors = case dict.get(state.monitors, source) {
      //   Ok(mon) -> {
      //     process.demonitor_process(mon)
      //     dict.delete(state.monitors, source)
      //   }
      //   _ -> state.monitors
      // }
      // let state = State(..state, producers:, monitors:)
      // process.send(source, source.Unsubscribe(state.self))
      // case dict.is_empty(producers) {
      //   True -> {
      //     state.on_shutdown(state.state)
      //     actor.Stop(process.Normal)
      //   }
      //   False -> actor.continue(state)
      // }
    }
    source.ProducerDown(source) -> {
      todo
      // io.println("producer down")
      // let producers = dict.delete(state.producers, source)
      // let monitors = dict.delete(state.monitors, source)
      // let state = State(..state, producers:, monitors:)
      // io.debug(producers)
      // case dict.is_empty(producers) {
      //   True -> {
      //     state.on_shutdown(state.state)
      //     actor.Stop(process.Normal)
      //   }
      //   False -> actor.continue(state)
      // }
    }
  }
}
