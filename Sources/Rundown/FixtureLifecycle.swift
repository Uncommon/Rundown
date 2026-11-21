/// A fixture phase is on the example's path while its user code runs, so
/// assertions as well as thrown errors can identify setup and cleanup.
enum FixturePhase: String, TestElement {
  case setup = "fixture setup"
  case cleanup = "fixture cleanup"

  var description: String { rawValue }
  var traits: [any Trait] { [] }
}

/// Carries every lifecycle error to the leaf runner. Classification happens
/// on the original errors, preserving skips and already-reported assertions.
struct FixtureErrors: Error {
  struct Failure: Sendable {
    let phase: FixturePhase?
    let error: any Error
  }

  let failures: [Failure]
}

enum FixtureExecution {
  // Matches the host's cancellation policy between fixture setup and the
  // example, just as the traversal checks it after a beforeEach hook.
  @TaskLocal static var shouldStop: @Sendable () -> Bool = { false }
}

@DeAsyncRD
func runFixture<Value>(
  make: @Sendable () async throws -> Value,
  cleanup: @Sendable (Value) async throws -> Void,
  execute: @Sendable (Value) async throws -> Void
) async throws {
  let value: Value
  do {
    value = try await ExampleRunner.$elementStack.withValue(ExampleRunner.elementStack + [FixturePhase.setup]) {
      try await make()
    }
  } catch {
    throw FixtureErrors(failures: [.init(phase: .setup, error: error)])
  }

  var failures: [FixtureErrors.Failure] = []
  if !FixtureExecution.shouldStop() {
    do { try await execute(value) }
    catch { failures.append(.init(phase: nil, error: error)) }
  }
  do {
    try await ExampleRunner.$elementStack.withValue(ExampleRunner.elementStack + [FixturePhase.cleanup]) {
      try await cleanup(value)
    }
  } catch {
    failures.append(.init(phase: .cleanup, error: error))
  }
  if !failures.isEmpty { throw FixtureErrors(failures: failures) }
}

// Keep all three callbacks on the main actor. In particular, returning Value
// from the factory must not send a non-Sendable AppKit value across actors.
@DeAsyncRD
@MainActor
func runMainActorFixture<Value>(
  make: @Sendable @MainActor () async throws -> Value,
  cleanup: @Sendable @MainActor (Value) async throws -> Void,
  execute: @Sendable @MainActor (Value) async throws -> Void
) async throws {
  let value: Value
  do {
    value = try await ExampleRunner.$elementStack.withValue(ExampleRunner.elementStack + [FixturePhase.setup]) {
      try await make()
    }
  } catch {
    throw FixtureErrors(failures: [.init(phase: .setup, error: error)])
  }

  var failures: [FixtureErrors.Failure] = []
  if !FixtureExecution.shouldStop() {
    do { try await execute(value) }
    catch { failures.append(.init(phase: nil, error: error)) }
  }
  do {
    try await ExampleRunner.$elementStack.withValue(ExampleRunner.elementStack + [FixturePhase.cleanup]) {
      try await cleanup(value)
    }
  } catch {
    failures.append(.init(phase: .cleanup, error: error))
  }
  if !failures.isEmpty { throw FixtureErrors(failures: failures) }
}
