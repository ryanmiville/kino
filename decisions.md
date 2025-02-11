# Decisions

* one handler loop for `cast` and `call`
  * `call` requires a `From(reply)` in the message type, modeled like `process.call`
  * handler takes a ref to self, so it can pass it to other processes
* no `handle_info`
  * impossible to make typesafe
  * instead have special `process_down` and `timeout` handlers
  * logs any unahndled messages
* only `local` named servers for now
* current recommended way to get a handle from a supervised server is to receive it on a `Subject` passed to `gen_server.child_spec_ack`

## Tradeoffs

* `system.get_state` is ugly since the underlying implementation holds more than just the state defined by the user
  * `sys.get_status` if formatted to omit the extra fields
* no `handle_info` means you can't send messages to yourself outside of the public API
  * you can still `cast` to yourself


## Questions/TODOs

* expose more functions from `gen_server`
* are there any other messages that get sent to `handle_info` that we want to handle?
* support non-local names
* is there a better way to get a reference to a server from a supervisor?
