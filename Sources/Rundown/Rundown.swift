/// Creates a copy of the attached function with the `async` and `await`
/// keywords stripped. All `async` functions called by the attached function
/// are assumed to have non-`async` variants. It also drops the
/// `@_disfavoredOverload` attribute, if present.
///
/// Optionally supply array literals of old and new metatypes for replacement
/// in the generated signature and generic constraints, such as
/// `replacing: [AsyncValue.self], with: [SyncValue.self]`. The arrays must have
/// the same number of entries. Qualified and compound types are supported.
/// Replacements can be combined with any `stripSendable` option.
/// Type spellings are matched syntactically; type aliases are not resolved.
///
/// This macro may also be applied to a non-`async` function to transform its
/// types and closure parameters.
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

/// Internal version of @DeAsync with the standard replacements of
/// AsyncCall -> SyncCall and AsyncMainCall -> SyncMainCall.
@attached(peer, names: overloaded)
internal macro DeAsyncRD(replacing oldTypes: [Any.Type] = [],
                         with newTypes: [Any.Type] = [],
                         stripSendable: StripSendable = .none)
  = #externalMacro(module: "RundownMacros", type: "DeAsyncMacro")

public enum StripSendable {
  case none, parameters, function, all
}
