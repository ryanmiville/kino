import gleam/erlang/process.{type Pid}
import kino
import kino/internal/supervisor as sup

pub type StaticChild(returning) {
  StaticChild(builder: sup.ChildBuilder, transform: fn(Pid) -> returning)
}

pub type DynamicChild(returning) {
  DynamicChild(spec: kino.Spec(returning), transform: fn(Pid) -> returning)
}
