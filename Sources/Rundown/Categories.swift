/// The time component of a phase
public protocol PhaseTime {}
public enum BeforeTime: PhaseTime {}
public enum ExampleTime: PhaseTime {}
public enum AfterTime: PhaseTime {}

/// The scope component of a phase
public protocol PhaseScope {}
public enum AllScope: PhaseScope {}
public enum EachScope: PhaseScope {}

/// The basis of a set of types that enables `Accumulator` to have different
/// types for different states in the builder's state machine. The various
/// protocols and enums are for categorizing the states.
public protocol AccumulatorPhase {
  associatedtype Time: PhaseTime
  associatedtype Scope: PhaseScope
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
