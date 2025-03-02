import gleeunit
import logging

pub fn main() {
  logging.configure()
  logging.set_level(logging.Debug)
  gleeunit.main()
}
