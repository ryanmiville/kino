import kino/dynamic_supervisor
import kino/supervisor.{type SupervisorRef}

pub fn spec() -> dynamic_supervisor.Spec(SupervisorRef) {
  use _ <- dynamic_supervisor.init()
  dynamic_supervisor.supervisor_children(dynamic_supervisor.Permanent)
}
