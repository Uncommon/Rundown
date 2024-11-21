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

public struct Accumulator<Phase: AccumulatorPhase> {
  typealias AccumulatorData = [ObjectIdentifier: [any Element]]

  var data: AccumulatorData = [:]

  init() {
    self.data = .init()
  }

  init(data: AccumulatorData) {
    self.data = data
  }

  init<OtherPhase: AccumulatorPhase>(other: Accumulator<OtherPhase>) {
    self.data = other.data
  }

  func adding(_ element: some Element) -> Self {
    var result = self
    result.data.appendOrSet(.init(Phase.self), element)
    return result
  }

  func transitioned<P: AccumulatorPhase>(with element: some Element) -> Accumulator<P> {
    .init().adding(element)
  }

  func phaseHooks<P: HookPhase>() -> [Hook<P>] {
    data[.init(P.self)]?.compactMap { $0 as? Hook<P> } ?? []
  }

  func examples() -> [ExampleGroup] {
    data[.init(ExampleGroup.self)]?.compactMap { $0 as? ExampleGroup } ?? []
  }
}

@resultBuilder
public struct ExampleBuilder {
  // BeforeEach and BeforeAll can start and repeat
  public static func buildPartialBlock<Phase: BeforePhase>(first: Hook<Phase>) -> Accumulator<Phase> {
    .init().adding(first)
  }
  public static func buildPartialBlock<Phase: BeforePhase>(
      accumulated: Accumulator<Phase>,
      next: Hook<Phase>) -> Accumulator<Phase> {
    accumulated.adding(next)
  }

  // BeforeEach can follow BeforeAll
  public static func buildPartialBlock(
      accumulated: Accumulator<BeforeAllPhase>,
      next: BeforeEach) -> Accumulator<BeforeEachPhase> {
    accumulated.transitioned(with: next)
  }

  // Examples can start and repeat
  public static func buildPartialBlock(first: any ExampleElement) -> Accumulator<ExamplePhase> {
    .init().adding(first)
  }
  public static func buildPartialBlock(
      accumulated: Accumulator<ExamplePhase>,
      next: any ExampleElement) -> Accumulator<ExamplePhase> {
    accumulated.adding(next)
  }

  // Examples can follow BeforeEach/BeforeAll
  public static func buildPartialBlock<Phase: BeforePhase>(
      accumulated: Accumulator<Phase>,
      next: any ExampleElement) -> Accumulator<ExamplePhase> {
    accumulated.transitioned(with: next)
  }

  // After hooks can follow examples
  public static func buildPartialBlock<Phase: AfterPhase>(
      accumulated: Accumulator<ExamplePhase>,
      next: Hook<Phase>) -> Accumulator<Phase> {
    accumulated.transitioned(with: next)
  }

  // After hooks can repeat
  public static func buildPartialBlock<Phase: AfterPhase>(
      accumulated: Accumulator<Phase>,
      next: Hook<Phase>) -> Accumulator<Phase> {
    accumulated.transitioned(with: next)
  }

  // AfterAll follows AfterEach
  public static func buildPartialBlock(
      accumulated: Accumulator<AfterEachPhase>,
      next: AfterAll) -> Accumulator<AfterAllPhase> {
    accumulated.transitioned(with: next)
  }

  // TODO: if/switch and for support

  // Examples or AfterEach/AfterAll can end
  public static func buildFinalResult<Phase: FinalPhase>(_ component: Accumulator<Phase>) -> ExampleGroup {
    .init(description: "",
          beforeAll: component.phaseHooks(),
          beforeEach: component.phaseHooks(),
          afterEach: component.phaseHooks(),
          afterAll: component.phaseHooks(),
          elements: component.examples())
  }

}
