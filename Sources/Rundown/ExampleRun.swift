import Foundation
import OSLog
import XCTest

/// Tracks the execution of an example group in order to construct the full name
/// of the current element.
public class ExampleRun: @unchecked Sendable {
  // Manual lock for unchecked sendability
  private let lock = NSRecursiveLock()
  internal static let logger = Logger(subsystem: "Rundown", category: "ExampleRun")

  var elementStack: [any TestElement] = []
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

  func with(_ element: some TestElement, block: () throws -> Void) rethrows {
    withLock { elementStack.append(element) }
    defer { withLock { _ = elementStack.popLast() } }
    try block()
  }

  func with(_ element: some TestElement, block: () async throws -> Void) async rethrows {
    withLock { elementStack.append(element) }
    defer { withLock { _ = elementStack.popLast() } }
    try await block()
  }

  /// Executes the elements of a group. This is managed by the run instead of
  /// the group itself because the run can have logic that it needs to apply
  /// at each step.
  public func run(_ group: ExampleGroup) throws {
    func runHooks<P>(_ hooks: [TestHook<P>]) throws {
      for hook in filterSkip(hooks) {
        try with(hook) {
          try hook.execute(in: self)
        }
      }
    }
    let elements = filterFocusSkip(group.elements)
    guard !elements.isEmpty
    else { return }
    
    try runHooks(group.beforeAll)
    for element in elements {
      try runHooks(group.beforeEach)
      try with(element) {
        switch element {
            case let subgroup as ExampleGroup:
              try run(subgroup)
            default:
                try element.execute(in: self)
        }
      }
      try runHooks(group.afterEach)
    }
    try runHooks(group.afterAll)
  }

  // same as above but with `await` sprinkled in
  public func run(_ group: ExampleGroup) async throws {
    func runHooks<P>(_ hooks: [TestHook<P>]) async throws {
      for hook in filterSkip(hooks) {
        try await with(hook) {
          try await hook.execute(in: self)
        }
      }
    }
    let elements = filterFocusSkip(group.elements)
    guard !elements.isEmpty
    else { return }

    try await runHooks(group.beforeAll)
    for element in elements {
      try await runHooks(group.beforeEach)
      try await with(element) {
        switch element {
          case let subgroup as ExampleGroup:
            try await run(subgroup)
          default:
            try await element.execute(in: self)
        }
      }
      try await runHooks(group.afterEach)
    }
    try await runHooks(group.afterAll)
  }

  func filterSkip(_ elements: [any TestElement]) -> [any TestElement] {
    elements.filter({ !$0.isSkipped })
  }
  
  func filterFocusSkip(_ elements: [any TestExample]) -> [any TestExample] {
    let nonSkipped = elements.filter { !$0.isSkipped }
    let focused = nonSkipped.filter(\.isDeepFocused)
    
    return focused.isEmpty ? nonSkipped : focused
  }
  
  public func run(_ within: Within) throws {
    try within.executor {
      try run(within.group)
    }
  }

  public static func run(_ element: some TestExample) throws {
    let run = ExampleRun()

    if let current {
      logger.error("running new element \"\(element.description)\" when already running \"\(current.description)\"")
    }
    try ExampleRun.$current.withValue(run) {
      try run.with(element) {
        try element.execute(in: run)
      }
    }
  }
}

