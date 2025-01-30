import iot/messages.{
  type Temperature, GetTemperature, RecordTemperature, TemperatureReading,
}
import kino/actor.{type ActorRef, type Behavior}
import kino/dynamic_supervisor.{type DynamicSupervisorRef}
import kino/supervisor.{type Child}

pub type Message =
  messages.Device

pub fn supervisor() -> dynamic_supervisor.Spec(ActorRef(Message)) {
  use _ <- dynamic_supervisor.init()
  dynamic_supervisor.worker_children(dynamic_supervisor.Permanent)
}

pub fn worker() -> actor.Spec(Message) {
  use _ <- actor.init()
  do_worker(Error(Nil))
}

fn do_worker(last_reading: Temperature) -> Behavior(Message) {
  use _, message <- actor.receive()
  case message {
    GetTemperature(request_id:, reply_to:) -> {
      actor.send(reply_to, TemperatureReading(request_id, last_reading))
      actor.continue
    }
    RecordTemperature(temperature) -> {
      do_worker(Ok(temperature))
    }
  }
}

pub fn child_spec(id: String) -> Child(DynamicSupervisorRef(ActorRef(Message))) {
  supervisor.supervisor_child(id, supervisor())
}
