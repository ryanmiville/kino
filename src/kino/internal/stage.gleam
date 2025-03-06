import gleam/bool
import gleam/deque.{type Deque}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type ProcessMonitor, type Selector, type Subject}
import gleam/function
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor.{type StartError}
import gleam/result
import gleam/set.{type Set}
import kino/internal/batch.{type Batch, type Demand, Batch, Demand}
import kino/internal/buffer.{type Buffer, Take}
import logging

type ProducerMessage(event) {
  Ask(demand: Int, consumer: Subject(ConsumerMessage(event)))
  Subscribe(consumer: Subject(ConsumerMessage(event)), demand: Int)
  Unsubscribe(consumer: Subject(ConsumerMessage(event)))
  ConsumerDown(consumer: Subject(ConsumerMessage(event)))
}

type ProcessorMessage(in, out) {
  ConsumerMessage(ConsumerMessage(in))
  ProducerMessage(ProducerMessage(out))
}

type ConsumerMessage(event) {
  NewEvents(events: List(event), from: Subject(ProducerMessage(event)))
  ConsumerSubscribe(
    source: Subject(ProducerMessage(event)),
    min_demand: Int,
    max_demand: Int,
  )
  ConsumerUnsubscribe(source: Subject(ProducerMessage(event)))
  ProducerDown(producer: Subject(ProducerMessage(event)))
}

pub type Produce(state, event) {
  Next(events: List(event), state: state)
  Done
}

pub type BufferStrategy {
  KeepFirst
  KeepLast
}

pub opaque type Consumer(event) {
  Consumer(subject: Subject(ConsumerMessage(event)))
}

pub opaque type Producer(event) {
  Producer(subject: Subject(ProducerMessage(event)))
}

pub opaque type Processor(in, out) {
  Processor(
    subject: Subject(ProcessorMessage(in, out)),
    consumer_subject: Subject(ConsumerMessage(in)),
    producer_subject: Subject(ProducerMessage(out)),
  )
}

pub fn as_consumer(processor: Processor(in, out)) {
  Consumer(processor.consumer_subject)
}

pub fn as_producer(processor: Processor(in, out)) {
  Producer(processor.producer_subject)
}

// ------------------------------
// Producer
// ------------------------------

pub fn start_producer(
  init init: fn() -> state,
  init_timeout init_timeout: Int,
  pull pull: fn(state, Int) -> Produce(state, event),
  buffer_strategy buffer_strategy: BufferStrategy,
  buffer_capacity buffer_capacity: Int,
) -> Result(Producer(event), StartError) {
  let ack = process.new_subject()
  actor.start_spec(actor.Spec(
    init: fn() {
      let state = init()
      let buf = buffer.new() |> buffer.capacity(buffer_capacity)
      let self = process.new_subject()
      let buffer = case buffer_strategy {
        KeepFirst -> buffer.keep(buf, buffer.First)
        KeepLast -> buffer.keep(buf, buffer.Last)
      }
      let selector =
        process.new_selector()
        |> process.selecting(self, function.identity)
      process.send(ack, self)
      let state =
        ProducerState(
          self: self,
          selector: selector,
          state: state,
          buffer: buffer,
          dispatcher: new_dispatcher(),
          consumers: set.new(),
          monitors: dict.new(),
          pull: pull,
        )
      actor.Ready(state, selector)
    },
    loop: producer_on_message,
    init_timeout: init_timeout,
  ))
  |> result.map(fn(_) { process.receive_forever(ack) |> Producer })
}

type ProducerState(state, event) {
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

fn producer_on_message(
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
      let dispatcher = dispatcher_subscribe(state.dispatcher, consumer)
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
      let dispatcher = dispatcher_cancel(state.dispatcher, consumer)
      let state = ProducerState(..state, consumers:, dispatcher:, monitors:)
      actor.continue(state)
    }
    ConsumerDown(consumer) -> {
      let consumers = set.delete(state.consumers, consumer)
      let monitors = dict.delete(state.monitors, consumer)
      let dispatcher = dispatcher_cancel(state.dispatcher, consumer)
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
  dispatcher_ask(state.dispatcher, demand, consumer)
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
        dispatch(state.dispatcher, state.self, events, demand - demand_left)
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
    dispatch(state.dispatcher, state.self, events, length)
  let buffer = buffer.store(state.buffer, events)
  ProducerState(..state, buffer: buffer, dispatcher: dispatcher)
}

// ------------------------------
// Consumer
// ------------------------------

pub fn start_consumer(
  init init: fn() -> state,
  init_timeout init_timeout: Int,
  handle_events handle_events: fn(state, List(event)) ->
    actor.Next(List(event), state),
  on_shutdown on_shutdown: fn(state) -> Nil,
) -> Result(Consumer(event), StartError) {
  let ack = process.new_subject()
  actor.start_spec(actor.Spec(
    init: fn() {
      let state = init()
      let self = process.new_subject()
      let selector =
        process.new_selector()
        |> process.selecting(self, function.identity)
      process.send(ack, self)
      let state =
        ConsumerState(
          self:,
          selector:,
          state:,
          handle_events: handle_events,
          on_shutdown: on_shutdown,
          producers: dict.new(),
          monitors: dict.new(),
        )
      actor.Ready(state, selector)
    },
    loop: consumer_on_message,
    init_timeout: init_timeout,
  ))
  |> result.map(fn(_) { process.receive_forever(ack) |> Consumer })
}

type ConsumerState(state, event) {
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

fn consumer_on_message(
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

// ----------------
// Processor
// ----------------

pub fn start_processor(
  init init: fn() -> state,
  init_timeout init_timeout: Int,
  handle_events handle_events: fn(state, List(in)) -> Produce(state, out),
  buffer_strategy buffer_strategy: BufferStrategy,
  buffer_capacity buffer_capacity: Option(Int),
) -> Result(Processor(in, out), StartError) {
  let ack = process.new_subject()
  actor.start_spec(actor.Spec(
    init: fn() {
      let state = init()
      let buffer = case buffer_capacity, buffer_strategy {
        Some(c), KeepFirst ->
          buffer.new() |> buffer.keep(buffer.First) |> buffer.capacity(c)
        Some(c), KeepLast ->
          buffer.new() |> buffer.keep(buffer.Last) |> buffer.capacity(c)
        None, KeepFirst -> buffer.new() |> buffer.keep(buffer.First)
        None, KeepLast -> buffer.new() |> buffer.keep(buffer.Last)
      }
      let self = process.new_subject()
      let consumer_self = process.new_subject()
      let producer_self = process.new_subject()

      let ps =
        process.new_selector()
        |> process.selecting(producer_self, ProducerMessage)
      let cs =
        process.new_selector()
        |> process.selecting(consumer_self, ConsumerMessage)

      let selector =
        process.new_selector()
        |> process.selecting(self, function.identity)
        |> process.merge_selector(ps)
        |> process.merge_selector(cs)

      process.send(ack, #(self, consumer_self, producer_self))
      let state =
        ProcessorState(
          self:,
          consumer_self:,
          producer_self:,
          selector:,
          state:,
          buffer:,
          dispatcher: new_dispatcher(),
          consumers: set.new(),
          producers: dict.new(),
          consumer_monitors: dict.new(),
          producer_monitors: dict.new(),
          events: Events(queue: deque.new(), demand: 0),
          handle_events: handle_events,
        )
      actor.Ready(state, selector)
    },
    loop: processor_on_message,
    init_timeout: init_timeout,
  ))
  |> result.map(fn(_) {
    let #(self, consumer_self, producer_self) = process.receive_forever(ack)
    Processor(self, consumer_self, producer_self)
  })
}

type ProcessorState(state, in, out) {
  ProcessorState(
    self: Subject(ProcessorMessage(in, out)),
    consumer_self: Subject(ConsumerMessage(in)),
    producer_self: Subject(ProducerMessage(out)),
    selector: Selector(ProcessorMessage(in, out)),
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

type Events(in) {
  Events(queue: Deque(#(List(in), Subject(ProducerMessage(in)))), demand: Int)
}

fn processor_on_message(
  message: ProcessorMessage(in, out),
  state: ProcessorState(state, in, out),
) {
  case message {
    ProducerMessage(message) -> processor_producer_on_message(message, state)
    ConsumerMessage(message) -> processor_consumer_on_message(message, state)
  }
}

fn processor_producer_on_message(
  message: ProducerMessage(out),
  state: ProcessorState(state, in, out),
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
      let dispatcher = dispatcher_subscribe(state.dispatcher, consumer)
      let monitors = state.consumer_monitors |> dict.insert(consumer, mon)
      let state =
        ProcessorState(
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
        dispatcher_ask(state.dispatcher, demand, consumer)

      let Events(queue, demand) = state.events
      let counter = counter + demand
      let state =
        ProcessorState(..state, dispatcher:, events: Events(queue, counter))

      let #(_, state) = processor_take_from_buffer(counter, state)
      let Events(queue, demand) = state.events
      take_events(queue, demand, state)
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
      let dispatcher = dispatcher_cancel(state.dispatcher, consumer)
      let state =
        ProcessorState(
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
      let dispatcher = dispatcher_cancel(state.dispatcher, consumer)
      let state =
        ProcessorState(
          ..state,
          consumers:,
          dispatcher:,
          consumer_monitors: monitors,
        )
      actor.continue(state)
    }
  }
}

fn processor_consumer_on_message(
  message: ConsumerMessage(in),
  state: ProcessorState(state, in, out),
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
        ProcessorState(
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
      take_events(queue, state.events.demand, state)
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
        ProcessorState(..state, producers:, producer_monitors: monitors)
      process.send(source, Unsubscribe(state.consumer_self))
      actor.continue(state)
    }
    ProducerDown(source) -> {
      let producers = dict.delete(state.producers, source)
      let monitors = dict.delete(state.producer_monitors, source)
      let state =
        ProcessorState(..state, producers:, producer_monitors: monitors)
      actor.continue(state)
    }
  }
}

fn processor_dispatch_events(
  state: ProcessorState(state, in, out),
  events: List(out),
  length: Int,
) {
  use <- bool.guard(events == [], { state })
  use <- bool.lazy_guard(set.is_empty(state.consumers), fn() {
    let buffer = buffer.store(state.buffer, events)
    ProcessorState(..state, buffer:)
  })
  let #(events, dispatcher) =
    dispatch(state.dispatcher, state.producer_self, events, length)

  let Events(queue, demand) = state.events
  let demand = demand - { length - list.length(events) }

  let buffer = buffer.store(state.buffer, events)
  ProcessorState(
    ..state,
    buffer: buffer,
    dispatcher: dispatcher,
    events: Events(queue, int.max(demand, 0)),
  )
}

fn take_events(
  queue: Deque(#(List(in), Subject(ProducerMessage(in)))),
  counter: Int,
  state: ProcessorState(state, in, out),
) -> actor.Next(ProcessorMessage(in, out), ProcessorState(state, in, out)) {
  use <- bool.lazy_guard(counter <= 0, fn() {
    let state = ProcessorState(..state, events: Events(queue, counter))
    actor.continue(state)
  })
  case deque.pop_front(queue) {
    Ok(#(#(events, from), queue)) -> {
      let state = ProcessorState(..state, events: Events(queue, counter))
      case send_events(events, from, state) {
        actor.Continue(state, _) ->
          take_events(state.events.queue, state.events.demand, state)
        actor.Stop(reason) -> actor.Stop(reason)
      }
    }
    Error(_) -> {
      actor.continue(ProcessorState(..state, events: Events(queue, counter)))
    }
  }
}

fn send_events(
  events: List(in),
  from: Subject(ProducerMessage(in)),
  state: ProcessorState(state, in, out),
) -> actor.Next(ProcessorMessage(in, out), ProcessorState(state, in, out)) {
  case dict.get(state.producers, from) {
    Ok(demand) -> {
      let #(current, batches) = batch.events(events, demand)
      let demand = Demand(..demand, current:)
      let producers = dict.insert(state.producers, from, demand)
      let state = ProcessorState(..state, producers:)
      processor_dispatch(state, batches, from)
    }
    Error(_) -> {
      // We queued but producer was removed
      let batches = [Batch(events, 0)]
      processor_dispatch(state, batches, from)
    }
  }
}

fn processor_dispatch(
  state: ProcessorState(state, in, out),
  batches: List(Batch(in)),
  from: Subject(ProducerMessage(in)),
) -> actor.Next(ProcessorMessage(in, out), ProcessorState(state, in, out)) {
  case batches {
    [] -> actor.continue(state)
    [Batch(events, size), ..rest] -> {
      case state.handle_events(state.state, events) {
        Next(events, new_state) -> {
          let state = ProcessorState(..state, state: new_state)
          let state =
            processor_dispatch_events(state, events, list.length(events))
          process.send(from, Ask(size, state.consumer_self))
          processor_dispatch(state, rest, from)
        }
        Done -> actor.Stop(process.Normal)
      }
    }
  }
}

fn processor_take_from_buffer(
  demand: Int,
  state: ProcessorState(state, in, out),
) -> #(Int, ProcessorState(state, in, out)) {
  let Take(buffer, demand_left, events) = buffer.take(state.buffer, demand)
  case events {
    [] -> #(demand, state)
    _ -> {
      let state =
        processor_dispatch_events(
          ProcessorState(..state, buffer:),
          events,
          demand - demand_left,
        )
      processor_take_from_buffer(demand_left, state)
    }
  }
}

// ----------------
// Dispatcher
// ----------------

type DispatchDemand(event) =
  #(Subject(ConsumerMessage(event)), Int)

type DemandDispatcher(event) {
  DemandDispatcher(
    demands: List(DispatchDemand(event)),
    pending: Int,
    max_demand: Option(Int),
  )
}

fn new_dispatcher() -> DemandDispatcher(event) {
  DemandDispatcher(demands: [], pending: 0, max_demand: None)
}

fn dispatcher_subscribe(
  dispatcher: DemandDispatcher(event),
  from: Subject(ConsumerMessage(event)),
) {
  DemandDispatcher(
    demands: list.append(dispatcher.demands, [#(from, 0)]),
    pending: dispatcher.pending,
    max_demand: dispatcher.max_demand,
  )
}

fn dispatcher_cancel(
  dispatcher: DemandDispatcher(event),
  from: Subject(ConsumerMessage(event)),
) {
  case list.key_pop(dispatcher.demands, from) {
    Error(Nil) -> dispatcher
    Ok(#(current, demands)) ->
      DemandDispatcher(
        demands: demands,
        pending: current + dispatcher.pending,
        max_demand: dispatcher.max_demand,
      )
  }
}

fn dispatcher_ask(
  dispatcher: DemandDispatcher(event),
  counter: Int,
  from: Subject(ConsumerMessage(event)),
) {
  let max = option.unwrap(dispatcher.max_demand, counter)

  case counter > max {
    True ->
      logging.log(
        logging.Warning,
        "Dispatcher expects a max demand of "
          <> int.to_string(max)
          <> " but got demand for "
          <> int.to_string(counter)
          <> " events",
      )
    _ -> Nil
  }
  let demands = case list.key_pop(dispatcher.demands, from) {
    Error(Nil) -> dispatcher.demands
    Ok(#(current, demands)) -> {
      add_demand(demands, from, current + counter)
    }
  }
  let already_sent = int.min(dispatcher.pending, counter)
  let dispatcher =
    DemandDispatcher(
      demands:,
      pending: dispatcher.pending - already_sent,
      max_demand: Some(max),
    )
  #(counter - already_sent, dispatcher)
}

fn dispatch(
  dispatcher: DemandDispatcher(event),
  self: Subject(ProducerMessage(event)),
  events: List(event),
  length: Int,
) {
  let #(events, demands) =
    dispatch_demand(dispatcher.demands, self, events, length)
  #(events, DemandDispatcher(..dispatcher, demands:))
}

fn dispatch_demand(
  demands: List(DispatchDemand(event)),
  self: Subject(ProducerMessage(event)),
  events: List(event),
  length: Int,
) {
  use <- bool.guard(events == [], #(events, demands))

  case demands {
    [] | [#(_, 0), ..] -> #(events, demands)
    [#(from, counter), ..rest] -> {
      let #(now, later, length, counter) = split_events(events, length, counter)
      process.send(from, NewEvents(now, self))
      let demands = add_demand(rest, from, counter)
      dispatch_demand(demands, self, later, length)
    }
  }
}

fn split_events(events: List(event), length: Int, counter: Int) {
  case length <= counter {
    True -> #(events, [], 0, counter - length)
    False -> {
      let #(now, later) = list.split(events, counter)
      #(now, later, length - counter, 0)
    }
  }
}

fn add_demand(
  demands: List(DispatchDemand(event)),
  from: Subject(ConsumerMessage(event)),
  counter: Int,
) {
  case demands {
    [] -> [#(from, counter)]
    [#(_, current), ..] if counter > current -> [#(from, counter), ..demands]
    [demand, ..rest] -> [demand, ..add_demand(rest, from, counter)]
  }
}

// ----------------
// helpers
// ----------------
pub fn subscribe(
  consumer consumer: Consumer(event),
  to producer: Producer(event),
  min_demand min_demand: Int,
  max_demand max_demand: Int,
) {
  process.send(
    consumer.subject,
    ConsumerSubscribe(producer.subject, min_demand, max_demand),
  )
}
