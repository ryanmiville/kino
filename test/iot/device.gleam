import gleam/erlang/process
import iot/messages.{
  type Temperature, GetTemperature, RecordTemperature, TemperatureReading,
}
import kino/actor.{type ActorRef, type Behavior}
import kino/child.{
  type DynamicChild, type StaticChild, DynamicChild, StaticChild,
}
import kino/dynamic_supervisor.{type DynamicSupervisorRef}

pub type Message =
  messages.Device

pub fn supervisor() -> dynamic_supervisor.Spec(ActorRef(Message)) {
  use _ <- dynamic_supervisor.init()
  dynamic_supervisor.worker_children(actor.owner)
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

pub fn worker_child_spec() -> DynamicChild(ActorRef(Message)) {
  actor.dynamic_child(worker())
}

pub fn supervisor_child_spec(
  id: String,
) -> StaticChild(DynamicSupervisorRef(ActorRef(Message))) {
  dynamic_supervisor.static_child(id, supervisor())
}
