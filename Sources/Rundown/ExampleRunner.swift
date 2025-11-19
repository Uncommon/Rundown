import Foundation
import OSLog
import Synchronization
import XCTest

/// Tracks the execution of an example group in order to construct the full name
/// of the current element.
public class ExampleRunner: @unchecked Sendable {
  // Manual lock for unchecked sendability
  private let lock = NSRecursiveLock()
  internal static let logger = Logger(subsystem: "Rundown", category: "ExampleRunner")

  var elementStack: [any TestElement] = []
  var description: String {
    withLock {
      elementStack.map { $0.description }.joined(separator: ", ")
    }
  }

  @TaskLocal
  static var current: ExampleRunner? = nil

  internal init() {}

  private func withLock<T>(_ block: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try block()
  }

  @DeAsyncRD
  func with(_ element: some TestElement, block: () async throws -> Void) async rethrows {
    withLock { elementStack.append(element) }
    defer { withLock { _ = elementStack.popLast() } }
    try await block()
  }

  /// Executes the elements of a group. This is managed by the runner instead of
  /// the group itself because the runner can have logic that it needs to apply
  /// at each step.
  public func run(_ group: ExampleGroup<SyncCall>) throws {
    @Sendable func runHooks<P>(_ hooks: [TestHook<P, SyncCall>]) throws {
      for hook in hooks.filter({ !$0.isExcluded }) {
        try with(hook) {
          try hook.execute(in: self)
        }
      }
    }
    @Sendable func runSubElement(_ element: some TestExample) throws {
      if group.aroundEachHooks.isEmpty {
        try runSubElementInner(element)
      }
      else {
        try runAround(hooks: group.aroundEachHooks, element: element)
      }
    }
    @Sendable func runAround(hooks: [AroundEach<SyncCall>], element: some TestExample) throws {
      if let hook = hooks.first {
        try hook.execute {
          try runAround(hooks: Array(hooks.dropFirst()),
                        element: element)
        }
      }
      else {
        try runSubElementInner(element)
      }
    }
    @Sendable func runSubElementInner(_ element: some TestExample) throws {
      try runHooks(group.beforeEachHooks)
      try with(element) {
        switch element {
          case let subgroup as ExampleGroup<SyncCall>:
            try run(subgroup)
          case let it as It<SyncCall>:
            try it.execute(in: self)
          case let within as Within<SyncCall>:
            try within.execute(in: self)
          case _ as ExampleGroup<AsyncCall>, _ as It<AsyncCall>:
            // TestBuilder<SyncCall> shouldn't accept any AsyncCall
            // elements, so this shouldn't happen.
            throw UnexpectedAsyncError()
          default:
            preconditionFailure("unexpected element type")
        }
      }
      try runHooks(group.afterEachHooks)
    }
    let elements = filterFocusSkip(group.elements)
    guard !elements.isEmpty
    else { return }
    
    try runHooks(group.beforeAllHooks)
    if group.traits.contains(where: { $0 is ConcurrentTrait }) {
      let errorMutex = Mutex<(any Error)?>(nil)
      
      DispatchQueue.concurrentPerform(iterations: elements.count) {
        let element = elements[$0]
        
        do {
          try runSubElement(element)
        }
        catch let elementError {
          errorMutex.withLock {
            if $0 == nil {
              $0 = elementError
            }
          }
        }
      }
      if let error = errorMutex.withLock({ $0 }) {
        throw error
      }
    }
    else {
      for element in elements {
        try runSubElement(element)
      }
    }
    try runHooks(group.afterAllHooks)
  }

  // same as above but with `await` sprinkled in
  public func run(_ group: ExampleGroup<AsyncCall>) async throws {
    func runHooks<P>(_ hooks: [TestHook<P, AsyncCall>]) async throws {
      for hook in filterExcluded(hooks) {
        try await with(hook) {
          try await hook.execute(in: self)
        }
      }
    }
    func runSubElement(_ element: some TestExample) async throws {
      // aroundEach
      try await runHooks(group.beforeEachHooks)
      try await with(element) {
        switch element {
          case let subgroup as ExampleGroup<AsyncCall>:
            try await run(subgroup)
          case let subgroup as ExampleGroup<SyncCall>:
            try run(subgroup)
          case let it as It<AsyncCall>:
            try await it.execute(in: self)
          case let it as It<SyncCall>:
            try it.execute(in: self)
          case let within as Within<AsyncCall>:
            try await within.execute(in: self)
          default:
            preconditionFailure("unexpected element type")
        }
      }
      try await runHooks(group.afterEachHooks)
    }
    
    let elements = filterFocusSkip(group.elements)
    guard !elements.isEmpty
    else { return }

    try await runHooks(group.beforeAllHooks)
    
    if group.traits.contains(where: { $0 is ConcurrentTrait }) {
      try await withThrowingTaskGroup(of: Void.self) { taskGroup in
        for element in elements {
          taskGroup.addTask {
            try await runSubElement(element)
          }
        }
        try await taskGroup.waitForAll()
      }
    }
    else {
      for element in elements {
        try await runSubElement(element)
      }
    }
    
    try await runHooks(group.afterAllHooks)
  }

  func filterExcluded<E: TestElement>(_ elements: [E]) -> [E] {
    elements.filter({ !$0.isExcluded })
  }
  
  func filterFocusSkip(_ elements: [any TestExample]) -> [any TestExample] {
    let nonSkipped = elements.filter { !$0.isExcluded }
    let focused = nonSkipped.filter(\.isDeepFocused)
    
    return focused.isEmpty ? nonSkipped : focused
  }

  @DeAsyncRD
  public func run(_ within: Within<AsyncCall>) async throws {
    try await within.executor {
      try await self.run(within.group)
    }
  }

  @DeAsyncRD
  public static func run(_ element: ExampleGroup<AsyncCall>) async throws {
    let runner = ExampleRunner()

    if let current {
      logger.error("running new element \"\(element.description)\" when already running \"\(current.description)\"")
    }
    try await ExampleRunner.$current.withValue(runner) {
      try await runner.with(element) {
        try await element.execute(in: runner)
      }
    }
  }
}

