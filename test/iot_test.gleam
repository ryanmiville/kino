import gleam/erlang/process
import gleeunit
import gleeunit/should
import iot/device
import iot/group
import iot/messages
import kino/actor
import kino/supervisor

pub fn main() {
  gleeunit.main()
}

pub fn device_no_temp_test() {
  let self = process.new_subject()
  let assert Ok(probe) = new_probe(self)

  let assert Ok(device_actor) = actor.start_link(device.worker())
  actor.send(device_actor, messages.GetTemperature(42, probe))

  process.receive(self, 10)
  |> should.equal(Ok(messages.TemperatureReading(42, Error(Nil))))
}

pub fn device_has_temp_test() {
  let self = process.new_subject()
  let assert Ok(probe) = new_probe(self)

  let assert Ok(device_actor) = actor.start_link(device.worker())
  actor.send(device_actor, messages.RecordTemperature(24.0))
  actor.send(device_actor, messages.RecordTemperature(55.0))

  actor.send(device_actor, messages.GetTemperature(42, probe))
  process.receive(self, 10)
  |> should.equal(Ok(messages.TemperatureReading(42, Ok(55.0))))
}

pub fn group_add_device_test() {
  let self = process.new_subject()
  let probe_subject = process.new_subject()
  let assert Ok(probe) = new_probe(probe_subject)

  let assert Ok(_) = supervisor.start_link(group.supervisor(self))
  let assert Ok(group_actor) = process.receive(self, 10)

  actor.send(group_actor, messages.AddDevice("device1"))
  actor.send(group_actor, messages.AddDevice("device2"))
  actor.send(group_actor, messages.AddDevice("device1"))
  actor.send(group_actor, messages.GetDeviceList(42, probe))
  process.receive(probe_subject, 10)
  |> should.equal(Ok(messages.DeviceList(42, ["device1", "device2"])))
}

fn new_probe(subject) {
  actor.init(fn(_) {
    use _, message <- actor.receive()
    process.send(subject, message)
    actor.continue()
  })
  |> actor.start_link
}
