import gleam/dict.{type Dict}
import iot/group
import kino/internal/supervisor as internal
import kino/supervisor.{type SupervisorRef}
import kino_old.{type ActorRef, type Behavior} as kino

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
  |> supervisor.add(supervisor.worker_child(
    "manager_worker",
    "manager_worker",
    worker(sup),
  ))
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
          // let asdf =
          //   supervisor.start_child(
          //     sup,
          //     supervisor.worker_child(
          //       "group_worker",
          //       "group_worker-" <> group_id,
          //       group.worker(group_id),
          //     ),
          //   )
          let group = kino.spawn_link(group.worker(group_id), group_id)
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
