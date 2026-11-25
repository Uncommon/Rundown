/// The declaration of an executable DSL element, independent of a test host.
/// Capture the components as default arguments at the public DSL boundary;
/// a default constructed here would point into Rundown instead of the caller.
package struct DeclarationLocation: Sendable, Equatable {
  package let fileID: String
  package let filePath: String
  package let line: Int
  package let column: Int
}
