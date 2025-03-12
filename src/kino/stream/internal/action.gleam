pub type Action(in, out) {
  Stop
  Continue(fn(in) -> Action(in, out))
  Emit(out, fn(in) -> Action(in, out))
}
