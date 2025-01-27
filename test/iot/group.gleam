import gleam/dict.{type Dict}
import iot/device
import kino_before.{type ActorRef} as kino

// import kino/internal/supervisor
import kino/supervisor_before.{type SupervisorRef} as supervisor

pub type Message {
  AddDevice(device_id: String)
  GetDeviceList(request_id: Int, reply_to: ActorRef(DeviceList))
}

pub type DeviceList {
  DeviceList(request_id: Int, ids: List(String))
}

pub fn worker(group_id: String, sup: SupervisorRef) -> kino.Spec(Message) {
  use _context <- kino.init()
  do_worker(group_id, sup, dict.new())
}

fn do_worker(
  group_id: String,
  sup: SupervisorRef,
  devices: Dict(String, ActorRef(device.Message)),
) {
  use _context, message <- kino.receive()
  case message {
    AddDevice(device_id) -> {
      case dict.get(devices, device_id) {
        Ok(_) -> {
          kino.continue
        }
        _ -> {
          let assert Ok(device) =
            supervisor.start_worker_child(sup, device.child_spec(device_id))
          do_worker(group_id, sup, dict.insert(devices, device_id, device))
        }
      }
    }
    GetDeviceList(request_id:, reply_to:) -> {
      let ids = dict.keys(devices)
      kino.send(reply_to, DeviceList(request_id, ids))
      kino.continue
    }
  }
}

pub fn child_spec(
  group_id: String,
  sup: SupervisorRef,
) -> supervisor.Child(ActorRef(Message)) {
  supervisor.worker_child("group_worker", worker(group_id, sup))
}
