import Foundation

/// A synchronous around hook cannot wrap the potentially suspending work of
/// an async spec. This applies to both `aroundEach` and `aroundEachPeer`.
public struct SynchronousAroundHookError: Error, CustomStringConvertible, LocalizedError {
  /// The groups containing the hook, followed by the hook's description.
  public let path: [String]

  public var description: String {
    "Synchronous around hook at \"\(path.joined(separator: ", "))\" cannot wrap async execution. "
      + "Declare the helper group and its around hook as async, and call the callback with 'try await'."
  }

  public var errorDescription: String? { description }
}
