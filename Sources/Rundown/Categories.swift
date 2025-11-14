// These protocols are used by the result builder to categorize elements into
// "phases" by ordering and scope, so that it can implement compile-time
// restrictions on element ordering.

/// The ordering component of a phase
public protocol PhaseOrdering {}
public enum BeforeOrdering: PhaseOrdering {}
public enum ExampleOrdering: PhaseOrdering {}
public enum AfterOrdering: PhaseOrdering {}

/// The scope component of a phase
public protocol PhaseScope {}
public enum AllScope: PhaseScope {}
public enum AroundScope: PhaseScope {}
public enum EachScope: PhaseScope {}

/// The basis of a set of types that enables `Accumulator` to have different
/// types for different states in the builder's state machine. The various
/// protocols and enums are for categorizing the states.
public protocol AccumulatorPhase: Sendable {
  associatedtype Ordering: PhaseOrdering
  associatedtype Scope: PhaseScope
}
/// Any "before" or "after" phase
public protocol HookPhase: AccumulatorPhase {
  static var phaseName: String { get }
}
/// Any phase that can come at the end - "example" or "after"
public protocol FinalPhase: AccumulatorPhase {}

public protocol BeforePhase: HookPhase where Ordering == BeforeOrdering {}
public protocol AfterPhase: FinalPhase, HookPhase where Ordering == AfterOrdering {}
public protocol AllPhase: HookPhase where Scope == AllScope {}
public protocol AroundPhase: HookPhase where Scope == AroundScope {}
public protocol EachPhase: HookPhase where Scope == EachScope {}
public enum BeforeAllPhase: BeforePhase, AllPhase {
  public static var phaseName: String { "before all" }
}
public enum AroundEachPhase: BeforePhase, AroundPhase {
  public static var phaseName: String { "around each" }
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
  public typealias Ordering = ExampleOrdering
  public typealias Scope = EachScope
}
