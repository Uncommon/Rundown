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
/// - parameter stripSendable: `@Sendable` can be stripped from
/// closure parameters and/or the function itself.
@attached(peer, names: overloaded)
public macro DeAsync(replacing oldTypes: [Any.Type] = [],
                     with newTypes: [Any.Type] = [],
                     stripSendable: StripSendable = .none)
  = #externalMacro(module: "RundownMacros", type: "DeAsyncMacro")

/// Internal version of @DeAsync with the standard replacement of
/// AsyncCall -> SyncCall
@attached(peer, names: overloaded)
internal macro DeAsyncRD(replacing oldTypes: [Any.Type] = [],
                         with newTypes: [Any.Type] = [],
                         stripSendable: StripSendable = .none)
  = #externalMacro(module: "RundownMacros", type: "DeAsyncMacro")

public enum StripSendable {
  case none, parameters, function, all
}
