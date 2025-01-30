import gleam/erlang/process.{type Subject}
import kino/actor.{type ActorRef}
import kino/supervisor
import ppool/serv

pub fn spec(limit: Int, ack: Subject(ActorRef(serv.Message))) -> supervisor.Spec {
  use self <- supervisor.init()
  supervisor.new(supervisor.OneForAll)
  |> supervisor.add_worker("serv", serv.spec(limit, self, ack))
}
