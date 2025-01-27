# pekko vibes (but not under the hood)

```gleam
pub fn manager() {
  use context <- kino.actor()
  worker(dict.new())
  |> kino.supervise
}

fn worker(groups: Groups) {
  use context, message <- kino.receive()
  case message {
    AddDevice(group_id:, device_id:) -> {
      case dict.get(groups, group_id) {
        Ok(group) -> {
          kino.send(group, group.AddDevice(device_id))
          kino.continue
        }
        - -> {
          let assert Ok(group) = kino.start_sibling(context, group.group(group_id))
          kino.send(group, group.AddDevice(device_id))
          worker(dict.insert(groups, group_id, group))
        }
      }
    }
    GetDevices(group_id:, reply_to:) -> {
      case dict.get(groups, group_id) {
        Ok(group) -> {
          kino.send(group, group.GetDevices(reply_to))
        }
        - -> {
          kino.send(reply_to, [])
        }
      }
      kino.continue
    }
  }
}
```

```gleam
pub fn group(group_id: String) {
  use context <- kino.actor()
  worker(group_id, dict.new())
  |> kino.supervise
}

fn worker(group_id: String,
  device_sup: ActorRef(DynamicSupervisorMessage),
  devices: Devices,
) {
  use context, message <- kino.receive()
  case message {
    Start -> {
      let assert Ok(device_sup) = kino.start_sibling(context, device.supervisor())
      worker(group_id, device_sup, devices)
    }
    AddDevice(device_id:) -> {
      case dict.get(devices, device_id) {
        Ok(device) -> {
          kino.continue
        }
        - -> {
          let assert Ok(device) = kino.try_call(device_sup, StartChild(device_id), 10)
          let devices = dict.insert(devices, device_id, device)
          worker(group_id, device_sup, devices)
        }
      }
    }
    GetDevices(reply_to:) -> {
      kino.send(reply_to, dict.keys(devices))
      kino.continue
    }
  }
}
```

```gleam
pub fn supervisor() -> {
  use context <- kino.dynamic_supervisor()
  device
}

pub fn device(device_id: String) {
  use context <- kino.actor()
  worker(device_id, 0.0)
}

fn worker(device_id: String, temperature: Float) {
  use context, message <- kino.receive()
  case message {
    SetTemperature(temperature:) -> {
      worker(temperature)
    }
    GetTemperature(reply_to:) -> {
      kino.send(reply_to, temperature)
      kino.continue
    }
  }
}
```

```gleam
pub opaque type SupervisorMessage {
  Nothing
}

pub fn supervisor(init: fn(Context) -> List(Child)) {
  todo
}
```

```gleam
pub opaque type DynamicSupervisorMessage(init_arg) {
  StartChild(init_arg)
}


pub fn dynamic_supervisor(init: fn(Context) -> fn(init_arg) -> Behavior(child_message)) {
  todo
}
```

```gleam
pub opaque type Spec(ref) {
  Spec(returns: ref)
}

pub fn actor(init: fn(Context) -> Behavior(message)) -> Spec(ActorRef) {
  todo
}

pub fn supervisor(init: fn(Context) -> List(Child)) -> Spec(SupervisorRef) {
  todo
}

pub fn dynamic_supervisor(
  init: fn(Context) -> fn(init_arg) -> Spec(returns)
) -> Spec(DynamicSupervisorRef(init_arg, returns)) {
  todo
}

pub fn start_sibling(context: Context, spec: Spec(returns)) -> Result(returns, Dynamic) {
  todo
}

pub fn supervise(actor: Spec(ActorRef(message)) -> Spec(ActorRef(message)) {
  todo
}
```
