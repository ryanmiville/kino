import gleam/list

pub type Emit(a) {
  Continue(chunk: List(a), fn() -> Emit(a))
  Done(chunk: List(a))
}

// Public API for iteration
pub type Step(element, accumulator) {
  Next(elements: List(element), accumulator: accumulator)
  Stop
}

pub type Flow(a) {
  Pull(emit: fn() -> Emit(a))
}

pub fn from_list(chunk: List(a)) -> Flow(a) {
  Pull(fn() { Done(chunk) })
}

pub fn single(value: a) -> Flow(a) {
  from_list([value])
}

pub fn unfold_chunks(initial: state, f: fn(state) -> Step(a, state)) -> Flow(a) {
  do_unfold_chunks(initial, f) |> Pull
}

fn do_unfold_chunks(
  initial: state,
  f: fn(state) -> Step(a, state),
) -> fn() -> Emit(a) {
  fn() {
    case f(initial) {
      Next(chunk, new_state) -> Continue(chunk, do_unfold_chunks(new_state, f))
      Stop -> Done([])
    }
  }
}

pub fn unfold(initial: state, f: fn(state) -> Emit(a)) -> Flow(a) {
  Pull(fn() { f(initial) })
}

pub fn fold_chunks(
  flow: Flow(a),
  initial: acc,
  f: fn(acc, List(a)) -> acc,
) -> acc {
  case flow {
    Pull(emit) -> {
      do_fold_chunks(emit(), initial, f)
    }
  }
}

fn do_fold_chunks(emit: Emit(a), acc: acc, f: fn(acc, List(a)) -> acc) {
  case emit {
    Continue(chunk, next) -> {
      do_fold_chunks(next(), f(acc, chunk), f)
    }
    Done(chunk) -> {
      f(acc, chunk)
    }
  }
}

pub fn to_list(flow: Flow(a)) -> List(a) {
  to_chunks(flow)
  |> list.flatten
}

pub fn to_chunks(flow: Flow(a)) -> List(List(a)) {
  let f = fn(acc, chunk) -> List(List(a)) { [chunk, ..acc] }
  fold_chunks(flow, [], f) |> list.reverse
}

pub fn main() {
  let assert [1] = single(1) |> to_list
  let assert [1, 2, 3] = from_list([1, 2, 3]) |> to_list
}
