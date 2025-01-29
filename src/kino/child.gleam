import gleam/erlang/process.{type Pid}
import kino/internal/supervisor as sup

pub type Child(returning) {
  Child(builder: sup.ChildBuilder, transform: fn(Pid) -> returning)
}
