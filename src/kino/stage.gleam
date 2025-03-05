import gleam/erlang/process.{type Subject}

pub type ProducerMessage(event) {
  Ask(demand: Int, consumer: Subject(ConsumerMessage(event)))
  Subscribe(consumer: Subject(ConsumerMessage(event)), demand: Int)
  Unsubscribe(consumer: Subject(ConsumerMessage(event)))
  ConsumerDown(consumer: Subject(ConsumerMessage(event)))
}

pub type ProducerConsumerMessage(in, out) {
  ConsumerMessage(ConsumerMessage(in))
  ProducerMessage(ProducerMessage(out))
}

pub type ConsumerMessage(event) {
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
  Next(elements: List(event), state: state)
  Done
}

pub type BufferStrategy {
  KeepFirst
  KeepLast
}

pub fn subscribe(
  consumer consumer: Subject(ConsumerMessage(event)),
  to producer: Subject(ProducerMessage(event)),
  min_demand min_demand: Int,
  max_demand max_demand: Int,
) {
  process.send(consumer, ConsumerSubscribe(producer, min_demand, max_demand))
}
