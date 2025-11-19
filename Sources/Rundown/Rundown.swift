/// When attached to a function, generates a function after it prefixed
/// with "test", calling the original function's output `ExampleGroup`.
/// This requires the attached function to also use `@ExampleBuilder`
/// and return `ExampleGroup`.
@attached(peer, names: arbitrary)
public macro Example() = #externalMacro(module: "RundownMacros", type: "ExampleMacro")

// Peer macro turns this:
// @Example @ExampleBuilder func thing() throws -> ExampleGroup {
//   Describe("feature") {
//     It("does something") {
//       (test steps)
//     }
//   }
// }
// into this:
// func thing() throws -> ExampleGroup { ··· }
// func testThing() throws {
//   try ExampleRunner.run(thing())
// }

/// Creates a copy of the attached function with the `async` and `await`
/// keywords stripped. All `async` functions called by the attached function
/// are assumed to have non-`async` variants.
@attached(peer)
public macro DeAsync(_ replacements: [String:String] = [:])
  = #externalMacro(module: "RundownMacros", type: "DeAsyncMacro")
