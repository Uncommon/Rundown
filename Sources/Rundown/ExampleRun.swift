import Foundation
import OSLog
import XCTest

/// Tracks the execution of an example group in order to construct the full name
/// of the current element.
public class ExampleRun: @unchecked Sendable {
  // Manual lock for unchecked sendability
  private let lock = NSRecursiveLock()
  internal static let logger = Logger(subsystem: "Rundown", category: "ExampleRun")

  var elementStack: [any Element] = []
  var description: String {
    withLock {
      elementStack.map { $0.description }.joined(separator: ", ")
    }
  }

  @TaskLocal
  static var current: ExampleRun? = nil

  internal init() {}

  private func withLock<T>(_ block: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try block()
  }

  func with(_ element: some Element, block: () throws -> Void) rethrows {
    withLock { elementStack.append(element) }
    try block()
    withLock { _ = elementStack.popLast() }
  }
  
  @MainActor
  func with(_ element: some Element, block: @MainActor () throws -> Void) rethrows {
    withLock { elementStack.append(element) }
    try block()
    withLock { _ = elementStack.popLast() }
  }

  public static func run(_ element: some ExampleElement) throws {
    let run = ExampleRun()

    if let current {
      logger.error("running new element \"\(element.description)\" when already running \"\(current.description)\"")
    }
    try ExampleRun.$current.withValue(run) {
      try element.execute(in: run)
    }
  }
}
