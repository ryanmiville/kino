import kino/actor.{type ActorRef}

pub type Manager {
  AddGroupDevice(group_id: String, device_id: String)
  GetGroupDeviceList(
    request_id: Int,
    group_id: String,
    reply_to: ActorRef(DeviceList),
  )
  GroupTerminated(group_id: String)
  GroupAdded(group_id: String, group: ActorRef(Group))
  Shutdown
}

pub type Group {
  StartDeviceSupervisor
  AddDevice(device_id: String)
  GetDeviceList(request_id: Int, reply_to: ActorRef(DeviceList))
  DeviceTerminated(device_id: String)
}

pub type Device {
  GetTemperature(request_id: Int, reply_to: ActorRef(TemperatureReading))
  RecordTemperature(temperature: Float)
}

pub type TemperatureReading {
  TemperatureReading(request_id: Int, temperature: Temperature)
}

pub type Temperature =
  Result(Float, Nil)

pub type DeviceList {
  DeviceList(request_id: Int, ids: List(String))
}
