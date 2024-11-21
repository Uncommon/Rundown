/// The basis of a set of types that enables `Accumulator` to have different
/// types for different states in the builder's state machine.
public protocol AccumulatorPhase {
  associatedtype Time: HookTime
  associatedtype Scope: HookScope
}
/// Any "before" or "after" phase
public protocol HookPhase: AccumulatorPhase {}
/// Any phase that can come at the end - example or after
public protocol FinalPhase: AccumulatorPhase {}

public protocol BeforePhase: HookPhase where Time == BeforeTime {}
public protocol AfterPhase: FinalPhase, HookPhase where Time == AfterTime {}
public protocol AllPhase: HookPhase where Scope == AllScope {}
public protocol EachPhase: HookPhase where Scope == EachScope {}
public enum BeforeAllPhase: BeforePhase, AllPhase {}
public enum BeforeEachPhase: BeforePhase, EachPhase {}
public enum AfterEachPhase: AfterPhase, EachPhase {}
public enum AfterAllPhase: AfterPhase, AllPhase {}
public enum ExamplePhase: FinalPhase {
  public typealias Time = ExampleTime
  public typealias Scope = EachScope
}

extension Dictionary {
  /// Appends `element` to the existing array for `key`, or initializes it with
  /// `[element]` if the value has not yet been set.
  mutating func appendOrSet<Element>(_ key: Key,
                                     _ element: Element) where Value == Array<Element> {
    if keys.contains(key) {
      self[key]!.append(element)
    }
    else {
      self[key] = [element]
    }
  }
}

/// Contains the accumulated data so it can be passed from one `Accumulator`
/// to the next.
struct AccumulatorData {
  var storage: [ObjectIdentifier: [any Element]] = [:]

  mutating func accumulate<Phase: HookPhase>(_ hook: Hook<Phase>) {
    storage.appendOrSet(.init(Phase.self), hook)
  }

  mutating func accumulate(_ element: any ExampleElement) {
    storage.appendOrSet(.init(ExampleElement.self), element)
  }

  func phaseHooks<Phase: HookPhase>() -> [Hook<Phase>] {
    storage[.init(Phase.self)]?.compactMap { $0 as? Hook<Phase> } ?? []
  }

  func examples() -> [ExampleGroup] {
    storage[.init(ExampleGroup.self)]?.compactMap { $0 as? ExampleGroup } ?? []
  }
}

public struct Accumulator<Phase: AccumulatorPhase> {
  var data: AccumulatorData

  init() {
    self.data = .init()
  }

  init(data: AccumulatorData) {
    self.data = data
  }

  init<OtherPhase: AccumulatorPhase>(other: Accumulator<OtherPhase>) {
    self.data = other.data
  }
}

@resultBuilder
public struct ExampleBuilder {
  // Before hooks

  // BeforeEach and BeforeAll can start and repeat
  public static func buildPartialBlock<Phase: BeforePhase>(first: Hook<Phase>) -> Accumulator<Phase> {
    // TODO: make an "accumulating()" function
    var result = Accumulator<Phase>()
    result.data.accumulate(first)
    return result
  }
  public static func buildPartialBlock<Phase: BeforePhase>(
      accumulated: Accumulator<Phase>,
      next: Hook<Phase>) -> Accumulator<Phase> {
    var result = accumulated
    result.data.accumulate(next)
    return result
  }

  // BeforeEach can follow BeforeAll
  public static func buildPartialBlock(
      accumulated: Accumulator<BeforeAllPhase>,
      next: BeforeEach) -> Accumulator<BeforeEachPhase> {
    // TODO: make a transition function
    var result = Accumulator<BeforeEachPhase>(data: accumulated.data)
    result.data.accumulate(next)
    return result
  }

  // Examples can start and repeat
  public static func buildPartialBlock(first: any ExampleElement) -> Accumulator<ExamplePhase> {
    var result = Accumulator<ExamplePhase>()
    result.data.accumulate(first)
    return result
  }
  public static func buildPartialBlock(
      accumulated: Accumulator<ExamplePhase>,
      next: any ExampleElement) -> Accumulator<ExamplePhase> {
    var result = accumulated
    result.data.accumulate(next)
    return result
  }

  // Examples can follow BeforeEach/BeforeAll
  public static func buildPartialBlock<Phase: BeforePhase>(
      accumulated: Accumulator<Phase>,
      next: any ExampleElement) -> Accumulator<ExamplePhase> {
    var result = Accumulator<ExamplePhase>(data: accumulated.data)
    result.data.accumulate(next)
    return result
  }

  // After hooks can follow examples
  public static func buildPartialBlock<Phase: AfterPhase>(
      accumulated: Accumulator<ExamplePhase>,
      next: Hook<Phase>) -> Accumulator<Phase> {
    var result = Accumulator<Phase>(data: accumulated.data)
    result.data.accumulate(next)
    return result
  }

  // After hooks can repeat
  public static func buildPartialBlock<Phase: AfterPhase>(
      accumulated: Accumulator<Phase>,
      next: Hook<Phase>) -> Accumulator<Phase> {
    var result = Accumulator<Phase>(data: accumulated.data)
    result.data.accumulate(next)
    return result
  }

  // AfterAll follows AfterEach
  public static func buildPartialBlock(
      accumulated: Accumulator<AfterEachPhase>,
      next: AfterAll) -> Accumulator<AfterAllPhase> {
    var result = Accumulator<AfterAllPhase>(data: accumulated.data)
    result.data.accumulate(next)
    return result
  }

  // TODO: if/switch and for support

  // Examples or AfterEach/AfterAll can end
  public static func buildFinalResult<Phase: FinalPhase>(_ component: Accumulator<Phase>) -> ExampleGroup {
    .init(description: "",
          beforeAll: component.data.phaseHooks(),
          beforeEach: component.data.phaseHooks(),
          afterEach: component.data.phaseHooks(),
          afterAll: component.data.phaseHooks(),
          elements: component.data.examples())
  }

}
