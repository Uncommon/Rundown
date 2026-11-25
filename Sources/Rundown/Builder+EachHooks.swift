// Per-example hooks share the existing builder stages with peer hooks:
// beforeAll, wrappers, setup, examples, cleanup, afterAll.
public extension ExampleBuilder {
  static func buildExpression(_ expression: AroundEach<Call>) -> AroundEach<Call> {
    expression
  }

  static func buildPartialBlock(first: AroundEach<Call>) -> Accumulator<AroundEachPhase> {
    .init().adding(first)
  }

  static func buildPartialBlock<Phase: AroundPhase>(accumulated: Accumulator<Phase>,
                                                    next: AroundEach<Call>) -> Accumulator<AroundEachPhase> {
    accumulated.transitioned(with: next)
  }

  static func buildPartialBlock(accumulated: Accumulator<BeforeAllPhase>,
                                next: AroundEach<Call>) -> Accumulator<AroundEachPhase> {
    accumulated.transitioned(with: next)
  }

  static func buildPartialBlock<C: CallType>(accumulated: Accumulator<BeforeAllPhase>,
                                             next: TestHook<BeforeEachPhase, C>) -> Accumulator<BeforeEachPhase> {
    accumulated.transitioned(with: next)
  }

  static func buildPartialBlock<Phase: AroundPhase, C: CallType>(accumulated: Accumulator<Phase>,
                                                                 next: TestHook<BeforeEachPhase, C>) -> Accumulator<BeforeEachPhase> {
    accumulated.transitioned(with: next)
  }

  static func buildPartialBlock<C: CallType>(accumulated: Accumulator<AroundEachPhase>,
                                             next: TestHook<BeforeEachPeerPhase, C>) -> Accumulator<BeforeEachPeerPhase> {
    accumulated.transitioned(with: next)
  }

  static func buildPartialBlock<C: CallType>(accumulated: Accumulator<BeforeEachPhase>,
                                             next: TestHook<BeforeEachPeerPhase, C>) -> Accumulator<BeforeEachPeerPhase> {
    accumulated.transitioned(with: next)
  }

  static func buildPartialBlock<C: CallType>(accumulated: Accumulator<BeforeEachPeerPhase>,
                                             next: TestHook<BeforeEachPhase, C>) -> Accumulator<BeforeEachPhase> {
    accumulated.transitioned(with: next)
  }

  static func buildPartialBlock(accumulated: Accumulator<AfterEachPhase>,
                                next: TestHook<AfterAllPhase, Call>) -> Accumulator<AfterAllPhase> {
    accumulated.transitioned(with: next)
  }

  static func buildPartialBlock(accumulated: Accumulator<AfterEachPhase>,
                                next: TestHook<AfterEachPeerPhase, Call>) -> Accumulator<AfterEachPeerPhase> {
    accumulated.transitioned(with: next)
  }

  static func buildPartialBlock(accumulated: Accumulator<AfterEachPeerPhase>,
                                next: TestHook<AfterEachPhase, Call>) -> Accumulator<AfterEachPhase> {
    accumulated.transitioned(with: next)
  }

  @available(*, unavailable, message: "BeforeAll must precede BeforeEach")
  static func buildPartialBlock<C: CallType>(accumulated: Accumulator<BeforeEachPhase>,
                                             next: TestHook<BeforeAllPhase, C>) -> Accumulator<BeforeEachPhase> {
    fatalError("unavailable")
  }

  @available(*, unavailable, message: "BeforeEach cannot appear after examples")
  static func buildPartialBlock<C: CallType>(accumulated: Accumulator<ExamplePhase>,
                                             next: TestHook<BeforeEachPhase, C>) -> Accumulator<ExamplePhase> {
    fatalError("unavailable")
  }

  @available(*, unavailable, message: "AfterEach must precede AfterAll")
  static func buildPartialBlock<C: CallType>(accumulated: Accumulator<AfterAllPhase>,
                                             next: TestHook<AfterEachPhase, C>) -> Accumulator<AfterAllPhase> {
    fatalError("unavailable")
  }

  @available(*, unavailable, message: "AroundEach cannot appear after examples")
  static func buildPartialBlock(accumulated: Accumulator<ExamplePhase>,
                                next: AroundEach<Call>) -> Accumulator<ExamplePhase> {
    fatalError("unavailable")
  }

  @available(*, unavailable, message: "Conditional must end in example or 'after' element")
  static func buildOptional(_ component: Accumulator<AroundEachPhase>?) -> Accumulator<ExamplePhase> {
    fatalError("unavailable")
  }

  @available(*, unavailable, message: "Conditional must end in example or 'after' element")
  static func buildOptional(_ component: Accumulator<BeforeEachPhase>?) -> Accumulator<ExamplePhase> {
    fatalError("unavailable")
  }

  @available(*, unavailable, message: "Conditional without 'else' must end in an example")
  static func buildOptional(_ component: Accumulator<AfterEachPhase>?) -> Accumulator<ExamplePhase> {
    fatalError("unavailable")
  }
}

public extension ExampleBuilder where Call: AsyncConvertibleCallType {
  static func buildPartialBlock(accumulated: Accumulator<BeforeAllPhase>,
                                next: TestHook<BeforeEachPhase, Call.SyncVersion>) -> Accumulator<BeforeEachPhase> {
    accumulated.transitioned(with: TestHook<BeforeEachPhase, Call>(fromSync: next))
  }

  static func buildPartialBlock<Phase: AroundPhase>(accumulated: Accumulator<Phase>,
                                                    next: TestHook<BeforeEachPhase, Call.SyncVersion>) -> Accumulator<BeforeEachPhase> {
    accumulated.transitioned(with: TestHook<BeforeEachPhase, Call>(fromSync: next))
  }

  static func buildPartialBlock(accumulated: Accumulator<AroundEachPhase>,
                                next: TestHook<BeforeEachPeerPhase, Call.SyncVersion>) -> Accumulator<BeforeEachPeerPhase> {
    accumulated.transitioned(with: TestHook<BeforeEachPeerPhase, Call>(fromSync: next))
  }

  static func buildPartialBlock(accumulated: Accumulator<BeforeEachPhase>,
                                next: TestHook<BeforeEachPeerPhase, Call.SyncVersion>) -> Accumulator<BeforeEachPeerPhase> {
    accumulated.transitioned(with: TestHook<BeforeEachPeerPhase, Call>(fromSync: next))
  }

  static func buildPartialBlock(accumulated: Accumulator<BeforeEachPeerPhase>,
                                next: TestHook<BeforeEachPhase, Call.SyncVersion>) -> Accumulator<BeforeEachPhase> {
    accumulated.transitioned(with: TestHook<BeforeEachPhase, Call>(fromSync: next))
  }

  static func buildPartialBlock(accumulated: Accumulator<AfterEachPhase>,
                                next: TestHook<AfterAllPhase, Call.SyncVersion>) -> Accumulator<AfterAllPhase> {
    accumulated.transitioned(with: TestHook<AfterAllPhase, Call>(fromSync: next))
  }

  static func buildPartialBlock(accumulated: Accumulator<AfterEachPhase>,
                                next: TestHook<AfterEachPeerPhase, Call.SyncVersion>) -> Accumulator<AfterEachPeerPhase> {
    accumulated.transitioned(with: TestHook<AfterEachPeerPhase, Call>(fromSync: next))
  }

  static func buildPartialBlock(accumulated: Accumulator<AfterEachPeerPhase>,
                                next: TestHook<AfterEachPhase, Call.SyncVersion>) -> Accumulator<AfterEachPhase> {
    accumulated.transitioned(with: TestHook<AfterEachPhase, Call>(fromSync: next))
  }

  @available(*, unavailable, message: "Every aroundEach must be async in an async test")
  static func buildExpression(_ expression: AroundEach<Call.SyncVersion>) -> AroundEach<Call> {
    fatalError("unavailable")
  }
}
