import kino/gen_server.{type GenServer}

pub type GenStage(event) =
  GenServer(Message(event))

pub type DemandMode {
  Forward
  Accumulate
}

pub type From(reply) =
  gen_server.From(reply)

pub type Message(event) {
  AskDemand(demand: Int, consumer: GenStage(event))
  GetDemandMode(from: From(DemandMode))
  SetDemandMode(mode: DemandMode)
  SendEvents(events: List(event))
  ConsumerSubscribe(producer: GenStage(event), from: From(Bool))
  ProducerSubscribe(consumer: GenStage(event))
  EstimateBufferCount(from: From(Int))
}
