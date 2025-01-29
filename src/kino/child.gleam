import kino/internal/supervisor as sup

pub type Child(returning) {
  Child(builder: sup.ChildBuilder(returning))
}
