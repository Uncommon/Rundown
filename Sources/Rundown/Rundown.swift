/// When attached to a function, transforms the body to use `ExampleBuilder`
/// to wrap the original body in a `Describe` element and execute it.
///
/// The down side of this is inherent in a function body macro: source
/// locations such as compile time errors, test failures, and breakpoints
/// are relative to the macro-generated body, not the original.
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
//   try ExampleRun.run(test)
// }

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
//   try ExampleRun.run(thing())
// }
