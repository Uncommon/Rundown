import Foundation
import OSLog

/// Tracks the execution of an example group in order to construct the full name
/// of the current element.
///
/// While a spec is running, `ExampleRunner.current` is the runner for it. That
/// is how code inside an example can find out which example it is in, such as to
/// name a log entry or an attachment.
public class ExampleRunner: @unchecked Sendable, CustomStringConvertible {
  internal static let logger = Logger(subsystem: "Rundown", category: "ExampleRunner")

  /// The elements that are running, outermost first, for the current task. This
  /// is a task-local instead of a property of the runner so that examples that
  /// run concurrently each have their own path: a child task starts with the
  /// stack of the group that started it, and what it pushes stays its own.
  ///
  /// Code that runs on other threads, such as `DispatchQueue.concurrentPerform()`,
  /// has to bind it again explicitly.
  @TaskLocal
  static var elementStack: [any TestElement] = []

  /// The descriptions of the elements that are running, from the outermost
  /// group down to the innermost: the spec, any enclosing `describe` and
  /// `context` groups, and the example or hook itself.
  ///
  /// This is the path of whatever is running in the calling task, so in a group
  /// with the `.concurrent` trait each example sees its own.
  public var path: [String] {
    Self.elementStack.map { $0.description }
  }

  /// The elements in `path` joined into a single string, such as
  /// "Spec, in a context, does a thing".
  public var description: String {
    path.joined(separator: ", ")
  }

  /// The runner for the spec that is running, or `nil` outside of a spec.
  @TaskLocal
  public static var current: ExampleRunner? = nil

  internal init() {}

  /// Runs a group and everything in it, with the plain error policy: every
  /// hook that should run does, and the first error is rethrown at the end.
  /// The runner and the path are set up by the node traversal.
  @DeAsyncRD
  public static func run(_ element: ExampleGroup<AsyncCall>) async throws {
    try await element.node.run(with: PlainReporter())
  }

  @DeAsyncRD @MainActor
  public static func run(_ element: ExampleGroup<AsyncMainCall>) async throws {
    try await element.node.run(with: PlainReporter())
  }
}
