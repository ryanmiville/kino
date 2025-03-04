import gleam/bool
import gleam/deque.{type Deque}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type ProcessMonitor, type Selector, type Subject}
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/set.{type Set}
import kino/stage.{type Produce, Done, Next}
import kino/stage/internal/batch.{type Batch, type Demand, Batch, Demand}
import kino/stage/internal/buffer.{type Buffer, Take}
import kino/stage/internal/gen_dispatcher.{DemandDispatcher}

pub fn subscribe(
  consumer consumer: Subject(ConsumerMessage(a)),
  to producer: Subject(ProducerMessage(a)),
  min_demand min_demand: Int,
  max_demand max_demand: Int,
) {
  process.send(consumer, ConsumerSubscribe(producer, min_demand, max_demand))
}

pub type ProducerMessage(a) {
  Ask(demand: Int, consumer: Subject(ConsumerMessage(a)))
  Subscribe(consumer: Subject(ConsumerMessage(a)), demand: Int)
  Unsubscribe(consumer: Subject(ConsumerMessage(a)))
  ConsumerDown(consumer: Subject(ConsumerMessage(a)))
}

pub type ProducerConsumerMessage(in, out) {
  ConsumerMessage(ConsumerMessage(in))
  ProducerMessage(ProducerMessage(out))
}

pub type ConsumerMessage(a) {
  NewEvents(events: List(a), from: Subject(ProducerMessage(a)))
  ConsumerSubscribe(
    source: Subject(ProducerMessage(a)),
    min_demand: Int,
    max_demand: Int,
  )
  ConsumerUnsubscribe(source: Subject(ProducerMessage(a)))
  ProducerDown(producer: Subject(ProducerMessage(a)))
}

pub type DemandDispatcher(event) =
  gen_dispatcher.DemandDispatcher(
    event,
    ProducerMessage(event),
    ConsumerMessage(event),
  )

pub fn new_dispatcher() {
  gen_dispatcher.new(NewEvents)
}

pub type ProducerState(state, event) {
  ProducerState(
    self: Subject(ProducerMessage(event)),
    selector: Selector(ProducerMessage(event)),
    state: state,
    buffer: Buffer(event),
    dispatcher: DemandDispatcher(event),
    consumers: Set(Subject(ConsumerMessage(event))),
    monitors: Dict(Subject(ConsumerMessage(event)), ProcessMonitor),
    pull: fn(state, Int) -> Produce(state, event),
  )
}

pub fn producer_on_message(
  message: ProducerMessage(event),
  state: ProducerState(state, event),
) {
  case message {
    Subscribe(consumer, demand) -> {
      let consumers = set.insert(state.consumers, consumer)
      let mon = process.monitor_process(process.subject_owner(consumer))
      let selector =
        process.new_selector()
        |> process.selecting_process_down(mon, fn(_) { ConsumerDown(consumer) })
        |> process.merge_selector(state.selector)
      process.send(state.self, Ask(demand, consumer))
      let dispatcher = gen_dispatcher.subscribe(state.dispatcher, consumer)
      let monitors = state.monitors |> dict.insert(consumer, mon)
      let state =
        ProducerState(..state, selector:, consumers:, dispatcher:, monitors:)
      actor.continue(state) |> actor.with_selector(selector)
    }
    Ask(demand:, consumer:) -> {
      producer_ask_demand(demand, consumer, state)
    }
    Unsubscribe(consumer) -> {
      let consumers = set.delete(state.consumers, consumer)
      let monitors = case dict.get(state.monitors, consumer) {
        Ok(mon) -> {
          process.demonitor_process(mon)
          dict.delete(state.monitors, consumer)
        }
        _ -> state.monitors
      }
      let dispatcher = gen_dispatcher.cancel(state.dispatcher, consumer)
      let state = ProducerState(..state, consumers:, dispatcher:, monitors:)
      actor.continue(state)
    }
    ConsumerDown(consumer) -> {
      let consumers = set.delete(state.consumers, consumer)
      let monitors = dict.delete(state.monitors, consumer)
      let dispatcher = gen_dispatcher.cancel(state.dispatcher, consumer)
      let state = ProducerState(..state, consumers:, dispatcher:, monitors:)
      actor.continue(state)
    }
  }
}

fn producer_ask_demand(
  demand: Int,
  consumer: Subject(ConsumerMessage(event)),
  state: ProducerState(state, event),
) {
  gen_dispatcher.ask(state.dispatcher, demand, consumer)
  |> producer_handle_dispatcher_result(state)
}

fn producer_handle_dispatcher_result(
  res: #(Int, DemandDispatcher(event)),
  state: ProducerState(state, event),
) {
  let #(counter, dispatcher) = res
  producer_take_from_buffer_or_pull(
    counter,
    ProducerState(..state, dispatcher:),
  )
}

fn producer_take_from_buffer_or_pull(
  demand: Int,
  state: ProducerState(state, event),
) {
  case producer_take_from_buffer(demand, state) {
    #(0, state) -> {
      actor.continue(state)
    }
    #(demand, state) -> {
      case state.pull(state.state, demand) {
        Next(events, new_state) -> {
          let state = ProducerState(..state, state: new_state)
          let state =
            producer_dispatch_events(state, events, list.length(events))
          actor.continue(state)
        }
        Done -> {
          actor.Stop(process.Normal)
        }
      }
    }
  }
}

fn producer_take_from_buffer(demand: Int, state: ProducerState(state, event)) {
  let Take(buffer, demand_left, events) = buffer.take(state.buffer, demand)
  case events {
    [] -> #(demand, state)
    _ -> {
      let #(events, dispatcher) =
        gen_dispatcher.dispatch(
          state.dispatcher,
          state.self,
          events,
          demand - demand_left,
        )
      let buffer = buffer.store(buffer, events)
      let state = ProducerState(..state, buffer: buffer, dispatcher: dispatcher)
      producer_take_from_buffer(demand_left, state)
    }
  }
}

fn producer_dispatch_events(
  state: ProducerState(state, event),
  events: List(event),
  length,
) {
  use <- bool.guard(events == [], state)
  use <- bool.lazy_guard(set.is_empty(state.consumers), fn() {
    let buffer = buffer.store(state.buffer, events)
    ProducerState(..state, buffer:)
  })

  let #(events, dispatcher) =
    gen_dispatcher.dispatch(state.dispatcher, state.self, events, length)
  let buffer = buffer.store(state.buffer, events)
  ProducerState(..state, buffer: buffer, dispatcher: dispatcher)
}

//
// CONSUMER
//

pub type ConsumerState(state, event) {
  ConsumerState(
    self: Subject(ConsumerMessage(event)),
    selector: Selector(ConsumerMessage(event)),
    state: state,
    handle_events: fn(state, List(event)) -> actor.Next(List(event), state),
    on_shutdown: fn(state) -> Nil,
    producers: Dict(Subject(ProducerMessage(event)), Demand),
    monitors: Dict(Subject(ProducerMessage(event)), ProcessMonitor),
  )
}

pub fn consumer_on_message(
  message: ConsumerMessage(event),
  state: ConsumerState(state, event),
) -> actor.Next(ConsumerMessage(event), ConsumerState(state, event)) {
  case message {
    ConsumerSubscribe(source, min, max) -> {
      let producers =
        dict.insert(state.producers, source, Demand(current: max, min:, max:))
      let mon = process.monitor_process(process.subject_owner(source))
      let selector =
        process.new_selector()
        |> process.selecting_process_down(mon, fn(_) { ProducerDown(source) })
        |> process.merge_selector(state.selector)

      let monitors = state.monitors |> dict.insert(source, mon)
      let state = ConsumerState(..state, selector:, producers:, monitors:)
      process.send(source, Subscribe(state.self, max))
      actor.continue(state) |> actor.with_selector(selector)
    }
    NewEvents(events:, from:) -> {
      case dict.get(state.producers, from) {
        Ok(demand) -> {
          let #(current, batches) = batch.events(events, demand)
          let demand = Demand(..demand, current:)
          let producers = dict.insert(state.producers, from, demand)
          let state = ConsumerState(..state, producers:)
          consumer_dispatch(state, batches, from)
        }
        Error(_) -> actor.continue(state)
      }
    }
    ConsumerUnsubscribe(source) -> {
      let producers = dict.delete(state.producers, source)
      let monitors = case dict.get(state.monitors, source) {
        Ok(mon) -> {
          process.demonitor_process(mon)
          dict.delete(state.monitors, source)
        }
        _ -> state.monitors
      }
      let state = ConsumerState(..state, producers:, monitors:)
      process.send(source, Unsubscribe(state.self))
      case dict.is_empty(producers) {
        True -> {
          state.on_shutdown(state.state)
          actor.Stop(process.Normal)
        }
        False -> actor.continue(state)
      }
    }
    ProducerDown(source) -> {
      let producers = dict.delete(state.producers, source)
      let monitors = dict.delete(state.monitors, source)
      let state = ConsumerState(..state, producers:, monitors:)
      case dict.is_empty(producers) {
        True -> {
          state.on_shutdown(state.state)
          actor.Stop(process.Normal)
        }
        False -> actor.continue(state)
      }
    }
  }
}

fn consumer_dispatch(
  state: ConsumerState(state, event),
  batches: List(Batch(event)),
  from: Subject(ProducerMessage(event)),
) -> actor.Next(ConsumerMessage(event), ConsumerState(state, event)) {
  case batches {
    [] -> actor.continue(state)
    [Batch(events, size), ..rest] -> {
      case state.handle_events(state.state, events) {
        actor.Continue(new_state, _) -> {
          let state = ConsumerState(..state, state: new_state)
          process.send(from, Ask(size, state.self))
          consumer_dispatch(state, rest, from)
        }
        actor.Stop(reason) -> actor.Stop(reason)
      }
    }
  }
}

//
// PRODUCER CONSUMER
//

pub type ProducerConsumerState(state, in, out) {
  ProducerConsumerState(
    self: Subject(ProducerConsumerMessage(in, out)),
    consumer_self: Subject(ConsumerMessage(in)),
    producer_self: Subject(ProducerMessage(out)),
    selector: Selector(ProducerConsumerMessage(in, out)),
    state: state,
    buffer: Buffer(out),
    dispatcher: DemandDispatcher(out),
    producers: Dict(Subject(ProducerMessage(in)), Demand),
    consumers: Set(Subject(ConsumerMessage(out))),
    producer_monitors: Dict(Subject(ProducerMessage(in)), ProcessMonitor),
    consumer_monitors: Dict(Subject(ConsumerMessage(out)), ProcessMonitor),
    events: Events(in),
    handle_events: fn(state, List(in)) -> Produce(state, out),
  )
}

pub type Events(in) {
  Events(queue: Deque(#(List(in), Subject(ProducerMessage(in)))), demand: Int)
}

pub fn pc_on_message(
  message: ProducerConsumerMessage(in, out),
  state: ProducerConsumerState(state, in, out),
) {
  case message {
    ProducerMessage(message) -> pc_on_producer_message(message, state)
    ConsumerMessage(message) -> pc_on_consumer_message(message, state)
  }
}

fn pc_on_producer_message(
  message: ProducerMessage(out),
  state: ProducerConsumerState(state, in, out),
) {
  case message {
    Subscribe(consumer, demand) -> {
      let consumers = set.insert(state.consumers, consumer)
      let mon = process.monitor_process(process.subject_owner(consumer))
      let selector =
        process.new_selector()
        |> process.selecting_process_down(mon, fn(_) {
          ProducerMessage(ConsumerDown(consumer))
        })
        |> process.merge_selector(state.selector)
      process.send(state.producer_self, Ask(demand, consumer))
      let dispatcher = gen_dispatcher.subscribe(state.dispatcher, consumer)
      let monitors = state.consumer_monitors |> dict.insert(consumer, mon)
      let state =
        ProducerConsumerState(
          ..state,
          selector:,
          consumers:,
          dispatcher:,
          consumer_monitors: monitors,
        )
      actor.continue(state) |> actor.with_selector(selector)
    }
    Ask(demand:, consumer:) -> {
      let #(counter, dispatcher) =
        gen_dispatcher.ask(state.dispatcher, demand, consumer)

      let Events(queue, demand) = state.events
      let counter = counter + demand
      let state =
        ProducerConsumerState(
          ..state,
          dispatcher:,
          events: Events(queue, counter),
        )

      let #(_, state) = pc_take_from_buffer(counter, state)
      let Events(queue, demand) = state.events
      pc_take_events(queue, demand, state)
    }
    Unsubscribe(consumer) -> {
      let consumers = set.delete(state.consumers, consumer)
      let monitors = case dict.get(state.consumer_monitors, consumer) {
        Ok(mon) -> {
          process.demonitor_process(mon)
          dict.delete(state.consumer_monitors, consumer)
        }
        _ -> state.consumer_monitors
      }
      let dispatcher = gen_dispatcher.cancel(state.dispatcher, consumer)
      let state =
        ProducerConsumerState(
          ..state,
          consumers:,
          dispatcher:,
          consumer_monitors: monitors,
        )
      actor.continue(state)
    }
    ConsumerDown(consumer) -> {
      let consumers = set.delete(state.consumers, consumer)
      let monitors = dict.delete(state.consumer_monitors, consumer)
      let dispatcher = gen_dispatcher.cancel(state.dispatcher, consumer)
      let state =
        ProducerConsumerState(
          ..state,
          consumers:,
          dispatcher:,
          consumer_monitors: monitors,
        )
      actor.continue(state)
    }
  }
}

fn pc_on_consumer_message(
  message: ConsumerMessage(in),
  state: ProducerConsumerState(state, in, out),
) {
  case message {
    ConsumerSubscribe(source, min, max) -> {
      let producers =
        dict.insert(state.producers, source, Demand(current: max, min:, max:))
      let mon = process.monitor_process(process.subject_owner(source))
      let selector =
        process.new_selector()
        |> process.selecting_process_down(mon, fn(_) {
          ConsumerMessage(ProducerDown(source))
        })
        |> process.merge_selector(state.selector)
      let monitors = state.producer_monitors |> dict.insert(source, mon)
      let state =
        ProducerConsumerState(
          ..state,
          selector:,
          producers:,
          producer_monitors: monitors,
        )
      process.send(source, Subscribe(state.consumer_self, max))
      actor.continue(state) |> actor.with_selector(selector)
    }
    NewEvents(events, from) -> {
      let queue = deque.push_back(state.events.queue, #(events, from))
      pc_take_events(queue, state.events.demand, state)
    }
    ConsumerUnsubscribe(source) -> {
      let producers = dict.delete(state.producers, source)
      let monitors = case dict.get(state.producer_monitors, source) {
        Ok(mon) -> {
          process.demonitor_process(mon)
          dict.delete(state.producer_monitors, source)
        }
        _ -> state.producer_monitors
      }
      let state =
        ProducerConsumerState(..state, producers:, producer_monitors: monitors)
      process.send(source, Unsubscribe(state.consumer_self))
      actor.continue(state)
    }
    ProducerDown(source) -> {
      let producers = dict.delete(state.producers, source)
      let monitors = dict.delete(state.producer_monitors, source)
      let state =
        ProducerConsumerState(..state, producers:, producer_monitors: monitors)
      actor.continue(state)
    }
  }
}

fn pc_dispatch_events(
  state: ProducerConsumerState(state, in, out),
  events: List(out),
  length: Int,
) {
  use <- bool.guard(events == [], { state })
  use <- bool.lazy_guard(set.is_empty(state.consumers), fn() {
    let buffer = buffer.store(state.buffer, events)
    ProducerConsumerState(..state, buffer:)
  })
  let #(events, dispatcher) =
    gen_dispatcher.dispatch(
      state.dispatcher,
      state.producer_self,
      events,
      length,
    )

  let Events(queue, demand) = state.events
  let demand = demand - { length - list.length(events) }

  let buffer = buffer.store(state.buffer, events)
  ProducerConsumerState(
    ..state,
    buffer: buffer,
    dispatcher: dispatcher,
    events: Events(queue, int.max(demand, 0)),
  )
}

fn pc_take_events(
  queue: Deque(#(List(in), Subject(ProducerMessage(in)))),
  counter: Int,
  stage: ProducerConsumerState(state, in, out),
) -> actor.Next(
  ProducerConsumerMessage(in, out),
  ProducerConsumerState(state, in, out),
) {
  use <- bool.lazy_guard(counter <= 0, fn() {
    let stage = ProducerConsumerState(..stage, events: Events(queue, counter))
    actor.continue(stage)
  })
  case deque.pop_front(queue) {
    Ok(#(#(events, from), queue)) -> {
      let stage = ProducerConsumerState(..stage, events: Events(queue, counter))
      case pc_send_events(events, from, stage) {
        actor.Continue(stage, _) ->
          pc_take_events(stage.events.queue, stage.events.demand, stage)
        actor.Stop(reason) -> actor.Stop(reason)
      }
    }
    Error(_) -> {
      actor.continue(
        ProducerConsumerState(..stage, events: Events(queue, counter)),
      )
    }
  }
}

fn pc_send_events(
  events: List(in),
  from: Subject(ProducerMessage(in)),
  stage: ProducerConsumerState(state, in, out),
) -> actor.Next(
  ProducerConsumerMessage(in, out),
  ProducerConsumerState(state, in, out),
) {
  case dict.get(stage.producers, from) {
    Ok(demand) -> {
      let #(current, batches) = batch.events(events, demand)
      let demand = Demand(..demand, current:)
      let producers = dict.insert(stage.producers, from, demand)
      let state = ProducerConsumerState(..stage, producers:)
      pc_dispatch(state, batches, from)
    }
    Error(_) -> {
      // We queued but producer was removed
      let batches = [Batch(events, 0)]
      pc_dispatch(stage, batches, from)
    }
  }
}

fn pc_dispatch(
  state: ProducerConsumerState(state, in, out),
  batches: List(Batch(in)),
  from: Subject(ProducerMessage(in)),
) -> actor.Next(
  ProducerConsumerMessage(in, out),
  ProducerConsumerState(state, in, out),
) {
  case batches {
    [] -> actor.continue(state)
    [Batch(events, size), ..rest] -> {
      case state.handle_events(state.state, events) {
        Next(events, new_state) -> {
          let state = ProducerConsumerState(..state, state: new_state)
          let state = pc_dispatch_events(state, events, list.length(events))
          process.send(from, Ask(size, state.consumer_self))
          pc_dispatch(state, rest, from)
        }
        Done -> actor.Stop(process.Normal)
      }
    }
  }
}

fn pc_take_from_buffer(
  demand: Int,
  state: ProducerConsumerState(state, in, out),
) -> #(Int, ProducerConsumerState(state, in, out)) {
  let Take(buffer, demand_left, events) = buffer.take(state.buffer, demand)
  case events {
    [] -> #(demand, state)
    _ -> {
      let state =
        pc_dispatch_events(
          ProducerConsumerState(..state, buffer:),
          events,
          demand - demand_left,
        )
      pc_take_from_buffer(demand_left, state)
    }
  }
}
