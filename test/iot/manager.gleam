import gleam/dict.{type Dict}
import gleam/erlang/process
import iot/group
import iot/messages.{
  AddGroupDevice, GetGroupDeviceList, GroupAdded, GroupTerminated, Shutdown,
}
import kino/actor.{type ActorRef, type Behavior}
import kino/supervisor.{type SupervisorRef}

pub type Message =
  messages.Manager

pub fn supervisor() {
  use self <- supervisor.init()
  let child = supervisor.worker_child("manager_worker", worker(self))
  supervisor.new(supervisor.OneForOne) |> supervisor.add_child(child)
}

fn worker(sup: SupervisorRef) {
  use _ <- actor.init()
  do_worker(sup, dict.new())
}

fn do_worker(
  sup: SupervisorRef,
  groups: Dict(String, ActorRef(group.Message)),
) -> Behavior(Message) {
  use _, message <- actor.receive()
  case message {
    AddGroupDevice(group_id:, device_id:) -> {
      case dict.get(groups, group_id) {
        Ok(group) -> {
          actor.send(group, messages.AddDevice(device_id))
          actor.continue
        }
        _ -> {
          let self = process.new_subject()
          let assert Ok(_) =
            supervisor.start_child(sup, group.child_spec(group_id, self))
          let assert Ok(group) = process.receive(self, 5000)
          actor.send(group, messages.AddDevice(device_id))
          do_worker(sup, dict.insert(groups, group_id, group))
        }
      }
    }
    GetGroupDeviceList(request_id:, group_id:, reply_to:) -> {
      case dict.get(groups, group_id) {
        Ok(group) -> {
          actor.send(group, messages.GetDeviceList(request_id, reply_to))
          actor.continue
        }
        _ -> {
          actor.send(reply_to, messages.DeviceList(request_id, []))
          actor.continue
        }
      }
    }
    GroupAdded(group_id:, group:) -> {
      do_worker(sup, dict.insert(groups, group_id, group))
    }
    GroupTerminated(group_id:) -> {
      do_worker(sup, dict.delete(groups, group_id))
    }
    Shutdown -> actor.stopped
  }
}
