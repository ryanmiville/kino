import kino_old.{type ActorRef, type Behavior} as kino

pub type Message {
  GetTemperature(request_id: Int, reply_to: ActorRef(TemperatureReading))
  RecordTemperature(temperature: Float)
}

pub type TemperatureReading {
  TemperatureReading(request_id: Int, temperature: Temperature)
}

pub type Temperature =
  Result(Float, Nil)

pub fn worker() -> Behavior(Message) {
  do_worker(Error(Nil))
}

fn do_worker(last_reading: Temperature) -> Behavior(Message) {
  use _context, message <- kino.receive()
  case message {
    GetTemperature(request_id:, reply_to:) -> {
      kino.send(reply_to, TemperatureReading(request_id, last_reading))
      kino.continue
    }
    RecordTemperature(temperature) -> {
      do_worker(Ok(temperature))
    }
  }
}
