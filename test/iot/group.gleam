import gleam/dict.{type Dict}
import gleam/erlang/process
import iot/device
import iot/messages.{AddDevice, DeviceList, GetDeviceList, StartDeviceSupervisor}
import kino/actor.{type ActorRef, type Behavior}
import kino/dynamic_supervisor.{type DynamicSupervisorRef}
import kino/supervisor.{type Child, type SupervisorRef}

pub type Message =
  messages.Group

pub fn supervisor(reply_to) {
  use self <- supervisor.init()
  let child = supervisor.worker_child("group_worker", worker(self, reply_to))
  supervisor.new() |> supervisor.add_child(child)
}

pub fn worker(sup: SupervisorRef, reply_to) -> actor.Spec(Message) {
  use self <- actor.init()
  actor.send(self, StartDeviceSupervisor)
  start_worker(sup, reply_to)
}

fn start_worker(sup: SupervisorRef, reply_to) -> Behavior(Message) {
  use self, message <- actor.receive()
  case message {
    StartDeviceSupervisor -> {
      let assert Ok(device_sup) =
        supervisor.start_child(sup, device.child_spec("device_supervisor"))
      process.send(reply_to, self)
      do_worker(device_sup, dict.new())
    }
    _ -> panic as "actor is not ready"
  }
}

fn do_worker(
  device_sup: DynamicSupervisorRef(ActorRef(device.Message)),
  devices: Dict(String, ActorRef(device.Message)),
) -> Behavior(Message) {
  use _, message <- actor.receive()
  case message {
    AddDevice(device_id) -> {
      case dict.get(devices, device_id) {
        Ok(_) -> {
          actor.continue
        }
        _ -> {
          let assert Ok(device) =
            dynamic_supervisor.start_child(device_sup, device.worker())
          do_worker(device_sup, dict.insert(devices, device_id, device))
        }
      }
    }
    GetDeviceList(request_id:, reply_to:) -> {
      let ids = dict.keys(devices)
      actor.send(reply_to, DeviceList(request_id, ids))
      actor.continue
    }
    StartDeviceSupervisor -> actor.continue
  }
}

pub fn child_spec(group_id: String, reply_to) -> Child(SupervisorRef) {
  supervisor.supervisor_child(group_id, supervisor(reply_to))
}
