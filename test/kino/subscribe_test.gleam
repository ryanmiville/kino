import kino/stage/consumer.{type Consumer}
import kino/stage/producer.{type Producer}
import kino/stage/producer_consumer.{type ProducerConsumer}
import kino/stage/subscribe

fn producer() -> Producer(a) {
  let assert Ok(prod) = producer.new(0) |> producer.start
  prod
}

fn producer_consumer() -> ProducerConsumer(a, b) {
  let assert Ok(pc) = producer_consumer.new(0) |> producer_consumer.start
  pc
}

fn consumer() -> Consumer(b) {
  let assert Ok(con) = consumer.new(0) |> consumer.start
  con
}

fn stages() -> #(Producer(a), ProducerConsumer(a, b), Consumer(b)) {
  let prod: Producer(a) = producer()
  let pc: ProducerConsumer(a, b) = producer_consumer()
  let con: Consumer(b) = consumer()
  #(prod, pc, con)
}

pub fn bottom_up_test() {
  let #(prod, pc, con) = stages()
  let _: Nil =
    subscribe.consumer(con)
    |> subscribe.max_demand(10)
    |> subscribe.through(pc)
    |> subscribe.max_demand(10)
    |> subscribe.min_demand(7)
    |> subscribe.to(prod)
}
