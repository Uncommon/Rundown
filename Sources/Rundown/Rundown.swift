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
///
/// Optionally you can supply lists of old and new types for replacement
/// for when they relate to `async` and non-`async` calls, respectively.
/// The two arrays should, of course, be the same length.
@attached(peer, names: overloaded)
public macro DeAsync(replacing oldTypes: [Any.Type] = [], with newTypes: [Any.Type] = [])
  = #externalMacro(module: "RundownMacros", type: "DeAsyncMacro")

/// Internal version of @DeAsync with the standard replacement of
/// AsyncCall -> SyncCall
@attached(peer, names: overloaded)
internal macro DeAsyncRD(replacing oldTypes: [Any.Type] = [], with newTypes: [Any.Type] = [])
  = #externalMacro(module: "RundownMacros", type: "DeAsyncMacro")

