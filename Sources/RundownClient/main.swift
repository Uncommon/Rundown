import Rundown

let a = 17
let b = 25

struct Suite {
  @Example @ExampleBuilder<SyncCall>
  func testThing() throws -> ExampleGroup<SyncCall> {
    it("works") {
    }
  }
}
