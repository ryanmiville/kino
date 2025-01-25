import gleam/dict.{type Dict}
import iot/group
import kino.{type ActorRef, type Behavior}
import kino/internal/supervisor as internal
import kino/supervisor.{type SupervisorRef}

pub type Message {
  AddDevice(group_id: String, device_id: String)
  GetDeviceList(
    request_id: Int,
    group_id: String,
    reply_to: ActorRef(DeviceList),
  )
  GroupTerminated(group_id: String)
  Shutdown
}

pub type DeviceList =
  group.DeviceList

pub fn supervisor() {
  use sup <- supervisor.init()

  supervisor.new(internal.OneForAll)
  |> supervisor.add(child_spec(sup))
}

fn worker(sup: SupervisorRef) {
  use _context <- kino.init()
  do_worker(sup, dict.new())
}

fn do_worker(
  sup: SupervisorRef,
  groups: Dict(String, ActorRef(group.Message)),
) -> Behavior(Message) {
  use _context, message <- kino.receive()
  case message {
    AddDevice(group_id:, device_id:) -> {
      case dict.get(groups, group_id) {
        Ok(group) -> {
          kino.send(group, group.AddDevice(device_id))
          kino.continue
        }
        _ -> {
          let assert Ok(group) =
            supervisor.start_worker_child(sup, group.child_spec(group_id, sup))
          kino.send(group, group.AddDevice(device_id))
          do_worker(sup, dict.insert(groups, group_id, group))
        }
      }
    }
    GetDeviceList(request_id:, group_id:, reply_to:) -> {
      case dict.get(groups, group_id) {
        Ok(group) -> {
          kino.send(group, group.GetDeviceList(request_id, reply_to))
          kino.continue
        }
        _ -> {
          kino.send(reply_to, group.DeviceList(request_id, []))
          kino.continue
        }
      }
    }
    GroupTerminated(group_id:) -> todo
    Shutdown -> todo
  }
  kino.continue
}

fn child_spec(sup: SupervisorRef) -> supervisor.Child(ActorRef(Message)) {
  supervisor.worker_child("manager_worker", worker(sup))
}
