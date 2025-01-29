import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Pid}
import gleam/pair
import gleam/result

pub type Spec(ref) {
  Spec(init: fn() -> Result(#(Pid, ref), Dynamic))
}

pub fn start_link(spec: Spec(ref)) -> Result(ref, Dynamic) {
  spec.init() |> result.map(pair.second)
}
