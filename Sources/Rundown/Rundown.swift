@attached(body)
public macro TestExample() = #externalMacro(module: "RundownMacros", type: "TestExampleMacro")

// function body macro that turns this:
// @Example func testThing() {
//   Describe("feature") {
//     It("does something") {
//       (test steps)
//     }
//   }
// }
// into this:
// func testThing() throws {
//   let test = Describe("Thing") { ··· }
//   try test.execute()
// }
