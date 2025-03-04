import gleam/erlang/process.{type Subject}

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

pub type Produce(state, a) {
  Next(elements: List(a), state: state)
  Done
}

pub type BufferStrategy {
  KeepFirst
  KeepLast
}

pub fn subscribe(
  consumer consumer: Subject(ConsumerMessage(a)),
  to producer: Subject(ProducerMessage(a)),
  min_demand min_demand: Int,
  max_demand max_demand: Int,
) {
  process.send(consumer, ConsumerSubscribe(producer, min_demand, max_demand))
}
