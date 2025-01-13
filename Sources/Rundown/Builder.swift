/// The basis of a set of types that enables `Accumulator` to have different
/// types for different states in the builder's state machine. The various
/// protocols and enums are for categorizing the states.
public protocol AccumulatorPhase {
  associatedtype Time: HookTime
  associatedtype Scope: HookScope
}
/// Any "before" or "after" phase
public protocol HookPhase: AccumulatorPhase {
  static var phaseName: String { get }
}
/// Any phase that can come at the end - example or after
public protocol FinalPhase: AccumulatorPhase {}

public protocol BeforePhase: HookPhase where Time == BeforeTime {}
public protocol AfterPhase: FinalPhase, HookPhase where Time == AfterTime {}
public protocol AllPhase: HookPhase where Scope == AllScope {}
public protocol EachPhase: HookPhase where Scope == EachScope {}
public enum BeforeAllPhase: BeforePhase, AllPhase {
  public static var phaseName: String { "before all" }
}
public enum BeforeEachPhase: BeforePhase, EachPhase {
  public static var phaseName: String { "before each" }
}
public enum AfterEachPhase: AfterPhase, EachPhase {
  public static var phaseName: String { "after each" }
}
public enum AfterAllPhase: AfterPhase, AllPhase {
  public static var phaseName: String { "after all" }
}
public enum ExamplePhase: FinalPhase {
  public typealias Time = ExampleTime
  public typealias Scope = EachScope
}

public struct EmptyElement: Element {
  public var description: String { "" }
  public var traits: [any Trait] { [] }
  public func execute(in run: ExampleRun) throws {}
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

  func adding<E: Element>(_ element: E) -> Self where Phase: HookPhase {
    var result = self
    result.data.appendOrSet(.init(E.self), element)
    return result
  }

  func adding<E: ExampleElement>(_ example: E) -> Self where Phase == ExamplePhase {
    var result = self
    result.data.appendOrSet(.init(ExampleElement.self), example)
    return result
  }

  mutating func add<E: ExampleElement>(_ example: E) where Phase == ExamplePhase {
    data.appendOrSet(.init(ExampleElement.self), example)
  }

  mutating func add<P: AccumulatorPhase>(_ other: Accumulator<P>) {
    data.merge(other.data) { first, second in
      first + second
    }
  }

  func transitioned<P: HookPhase>(with element: some Element) -> Accumulator<P> {
    .init(data: data).adding(element)
  }

  func transitioned(with element: some ExampleElement) -> Accumulator<ExamplePhase> {
    .init(data: data).adding(element)
  }

  func phaseHooks<P: HookPhase>(_ phase: P.Type) -> [Hook<P>] {
    data[.init(Hook<P>.self)]?.compactMap { $0 as? Hook<P> } ?? []
  }

  func examples() -> [ExampleElement] {
    data[.init(ExampleElement.self)]?.compactMap { $0 as? ExampleElement } ?? []
  }
}

@resultBuilder
public struct ExampleBuilder {
  // All hooks can repeat
  public static func buildPartialBlock<Phase: AccumulatorPhase>(
      accumulated: Accumulator<Phase>,
      next: Hook<Phase>) -> Accumulator<Phase> {
    accumulated.adding(next)
  }

  // BeforeEach and BeforeAll can start
  public static func buildPartialBlock<Phase: BeforePhase>(first: Hook<Phase>) -> Accumulator<Phase> {
    .init().adding(first)
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

  // AfterAll follows AfterEach
  public static func buildPartialBlock(
      accumulated: Accumulator<AfterEachPhase>,
      next: AfterAll) -> Accumulator<AfterAllPhase> {
    accumulated.transitioned(with: next)
  }

  // if/else for examples
  public static func buildEither<E: Element>(first component: E) -> E {
    component
  }
  public static func buildEither<E: Element>(second component: E) -> E {
    component
  }

  // Loops can end with examples or AfterEach/AfterAll
  public static func buildArray<P: FinalPhase>(_ components: [Accumulator<P>]) -> Accumulator<ExamplePhase> {
    var result = Accumulator<ExamplePhase>()

    for component in components {
      result.add(component)
    }
    return result
  }

  public static func buildPartialBlock<P>(first: Accumulator<P>) -> Accumulator<P> {
    first
  }

  // Examples or AfterEach/AfterAll can end
  public static func buildFinalResult<Phase: FinalPhase>(_ component: Accumulator<Phase>) -> ExampleGroup {
    // TODO: preserve the example description
    .init(description: "",
          traits: [],
          beforeAll: component.phaseHooks(BeforeAllPhase.self),
          beforeEach: component.phaseHooks(BeforeEachPhase.self),
          afterEach: component.phaseHooks(AfterEachPhase.self),
          afterAll: component.phaseHooks(AfterAllPhase.self),
          elements: component.examples())
  }

  // TODO: more messages for disallowed scenarios
  @available(*, unavailable, message: "Examples must not be empty")
  public static func buildBlock() -> Accumulator<ExamplePhase> {
    fatalError("unavailable")
  }
  @available(*, unavailable, message: "BeforeAll must precede BeforeEach")
  public static func buildPartialBlock(
      accumulated: Accumulator<BeforeEachPhase>,
      next: BeforeAll) -> Accumulator<BeforeEachPhase> {
    fatalError("unavailable")
  }
  @available(*, unavailable, message: "AfterEach must precede AfterAll")
  public static func buildPartialBlock(
      accumulated: Accumulator<AfterAllPhase>,
      next: AfterEach) -> Accumulator<AfterAllPhase> {
    fatalError("unavailable")
  }
  @available(*, unavailable, message: "Loop must end in example or after element")
  public static func buildArray<P: BeforePhase>(_ components: [Accumulator<P>]) -> Accumulator<P> {
    fatalError("unavailable")
  }
  @available(*, unavailable, message: "Group must have examples")
  public static func buildFinalResult<Phase: BeforePhase>(_ component: Accumulator<Phase>) -> ExampleGroup {
    fatalError("unavailable")
  }
}
