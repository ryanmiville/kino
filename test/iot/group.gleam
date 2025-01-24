import gleam/dict.{type Dict}
import iot/device
import kino.{type ActorRef, type Behavior}
import kino/supervisor

pub type Message {
  AddDevice(device_id: String)
  GetDeviceList(request_id: Int, reply_to: ActorRef(DeviceList))
}

pub type DeviceList {
  DeviceList(request_id: Int, ids: List(String))
}

pub fn worker(group_id: String) -> Behavior(Message) {
  use _context <- kino.init()
  do_worker(group_id, dict.new())
}

fn do_worker(group_id: String, devices: Dict(String, ActorRef(device.Message))) {
  use _context, message <- kino.receive()
  case message {
    AddDevice(device_id) -> {
      case dict.get(devices, device_id) {
        Ok(_) -> {
          kino.continue
        }
        _ -> {
          let assert Ok(device) = kino.start_link(device.worker())
          do_worker(group_id, dict.insert(devices, device_id, device))
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

pub fn child_spec(group_id: String) -> supervisor.Child(ActorRef(Message)) {
  supervisor.worker_child("group_worker", worker(group_id))
}
