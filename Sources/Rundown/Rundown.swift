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
/// are assumed to have non-`async` variants. It also drops the
/// `@_disfavoredOverload` attribute, if present.
///
/// Optionally you can supply lists of old and new types for replacement
/// for when they relate to `async` and non-`async` calls, respectively.
/// The two arrays should, of course, be the same length.
///
/// This macro may be applied to a non-`async` function, in which case it only
/// peforms the type replacement.
///
/// This macro was created to reduce internal code duplication for this package,
/// but it is made public in case it may be useful.
///
/// - parameter oldTypes: Types to be replaced
/// - parameter newTypes: Substitutions for types in `oldTypes`
/// - parameter stripSendable: If true, `@Sendable` will be stripped from
/// closure parameters.
@attached(peer, names: overloaded)
public macro DeAsync(replacing oldTypes: [Any.Type] = [],
                     with newTypes: [Any.Type] = [],
                     stripSendable: Bool = false)
  = #externalMacro(module: "RundownMacros", type: "DeAsyncMacro")

/// Internal version of @DeAsync with the standard replacement of
/// AsyncCall -> SyncCall
@attached(peer, names: overloaded)
internal macro DeAsyncRD(replacing oldTypes: [Any.Type] = [],
                         with newTypes: [Any.Type] = [],
                         stripSendable: Bool = false)
  = #externalMacro(module: "RundownMacros", type: "DeAsyncMacro")

