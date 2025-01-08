import Rundown

let a = 17
let b = 25

struct Suite {
  @Example @ExampleBuilder
  func testThing() throws -> ExampleGroup {
    It("works") {
    }
  }
}
