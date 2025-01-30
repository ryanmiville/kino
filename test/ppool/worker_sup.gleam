import kino/actor.{type ActorRef}
import kino/dynamic_supervisor

pub fn spec() -> dynamic_supervisor.Spec(ActorRef(message)) {
  use _ <- dynamic_supervisor.init()
  dynamic_supervisor.worker_children(dynamic_supervisor.Temporary)
}
