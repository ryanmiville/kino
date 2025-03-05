pub type Produce(state, event) {
  Next(elements: List(event), state: state)
  Done
}

pub type BufferStrategy {
  KeepFirst
  KeepLast
}
