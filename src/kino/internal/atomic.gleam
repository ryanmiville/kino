import atomic_array.{type AtomicArray}

pub opaque type AtomicInt {
  AtomicInt(array: AtomicArray)
}

pub fn new() -> AtomicInt {
  AtomicInt(atomic_array.new_signed(1))
}

pub fn get(int: AtomicInt) -> Int {
  let assert Ok(value) = atomic_array.get(int.array, 0)
  value
}

pub fn add(int: AtomicInt, amount: Int) -> Nil {
  let assert Ok(_) = atomic_array.add(int.array, 0, amount)
  Nil
}

pub fn add_get(int: AtomicInt, amount: Int) -> Int {
  let assert Ok(value) = do_add_get(int.array, 0, amount)
  value
}

pub fn set(int: AtomicInt, value: Int) -> Nil {
  let assert Ok(_) = atomic_array.set(int.array, 0, value)
  Nil
}

pub fn exchange(current int: AtomicInt, with value: Int) -> Int {
  let assert Ok(previous) = atomic_array.exchange(int.array, 0, value)
  previous
}

@external(erlang, "kino_ffi", "add_get")
fn do_add_get(array: AtomicArray, index: Int, amount: Int) -> Result(Int, Nil)
