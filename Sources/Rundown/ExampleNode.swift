/// A read-only description of a spec as a tree, which doesn't depend on the
/// call type of the `ExampleGroup` it was built from.
///
/// `ExampleGroup<Call>` is generic over four call types, so anything that
/// traverses one has to be written (or generated) once per call type. A node
/// has the same shape for all of them, with the differences reduced to
/// `isolation` and `execution`. It holds each closure as the call type it was
/// written with, so a traversal can run it.
///
/// ## Why there are two sets of types
///
/// `ExampleBuilder` and its `Accumulator` types, along with `ExampleGroup`,
/// `It`, `TestHook` and `AroundEach`, exist to be written against. They are
/// generic over the call type and over the phase (`BeforeAllPhase`,
/// `ExamplePhase` and so on) so that the compiler enforces the order and
/// structure of a spec: hooks before examples, `afterAll` last, no
/// `aroundEach` after an example, and a main-actor closure only where
/// main-actor elements are allowed. That is also why the DSL functions return
/// them, which makes them public API.
///
/// Once a spec is built, none of that is needed to run it, and the generics
/// get in the way: every traversal repeats for each call type. The node tree is
/// what the built group looks like with the builder's types removed. It is
/// derived from them and never built by hand, and nothing about order is
/// checked here, because by this point the builder has already guaranteed it.
/// Only the call-type split that can't be erased remains (see `Body`).
struct ExampleNode: Sendable {
  enum Kind: Hashable, Sendable {
    case group
    case example
    case hook(HookKind)
  }

  /// The place of a hook in the lifecycle of its group
  enum HookKind: CaseIterable, Hashable, Sendable {
    case beforeAll, aroundEach, beforeEach, afterEach, afterAll
  }

  enum Isolation: Hashable, Sendable {
    case nonisolated
    case mainActor
  }

  enum Execution: Hashable, Sendable {
    case sync
    case async
  }

  /// The closure of an example or hook, kept as the call type it was written
  /// with. Sync stays sync and main-actor stays main-actor, because the XCTest
  /// runner depends on both and neither can be erased: a sync closure can't
  /// be wrapped in an async one without making the runner async, and actor
  /// isolation is part of the closure's type.
  enum Body: Sendable {
    case sync(SyncCall.Callback)
    case async(AsyncCall.Callback)
    case syncMain(SyncMainCall.Callback)
    case asyncMain(AsyncMainCall.Callback)
  }

  /// The closure of an `aroundEach` hook, which takes the callback to wrap
  enum AroundBody: Sendable {
    case sync(SyncCall.AroundCallback)
    case async(AsyncCall.AroundCallback)
    case syncMain(SyncMainCall.AroundCallback)
    case asyncMain(AsyncMainCall.AroundCallback)
  }

  let kind: Kind
  /// The same text as the `description` of the element, so a hook's includes
  /// its phase, such as "before each: name".
  let name: String
  let traits: [any Trait]
  let isolation: Isolation
  let execution: Execution

  /// What running the node does, for examples and non-around hooks
  let body: Body?
  /// The wrapper of an `aroundEach` hook
  let around: AroundBody?

  /// The groups and examples directly inside a group, in order. Empty for
  /// examples and hooks.
  private(set) var children: [ExampleNode]

  /// The hooks of a group, in order within each kind. A hook applies to the
  /// children of the group that declares it, and a child group counts as one
  /// child, so each-hooks are not copied down to the examples of a nested
  /// group. Empty for examples and hooks.
  let hooks: [HookKind: [ExampleNode]]

  func hooks(_ kind: HookKind) -> [ExampleNode] {
    hooks[kind] ?? []
  }

  /// Whether the node runs, as far as its own group is concerned. This is
  /// resolved when the tree is built, and leaves excluded and unselected nodes
  /// in the tree so that it still has the structure of the spec.
  ///
  /// - A node with the `.excluded` trait is not selected.
  /// - If any non-excluded child of a group has a focused descendant, then
  ///   only those children are selected, and the rest are left out.
  /// - Otherwise every non-excluded child is selected.
  ///
  /// A node whose group is not selected doesn't run either, so a traversal
  /// only goes into nodes that are selected, from the root down. The root
  /// has no group to leave it out, and is always selected.
  private(set) var isSelected: Bool = true

  /// The children that run, in order
  var selectedChildren: [ExampleNode] {
    children.filter(\.isSelected)
  }

  /// The hooks of the given kind that run, in order
  func selectedHooks(_ kind: HookKind) -> [ExampleNode] {
    hooks(kind).filter(\.isSelected)
  }

  var isGroup: Bool { kind == .group }
  var isExample: Bool { kind == .example }

  var isExcluded: Bool { traits.contains { $0 is ExcludedTrait } }
  var isFocused: Bool { traits.contains { $0 is FocusedTrait } }
  var isConcurrent: Bool { traits.contains { $0 is ConcurrentTrait } }

  /// Whether this node or any descendant is focused. Excluded descendants
  /// count, the same as `TestExample.isDeepFocused` for a group.
  var isDeepFocused: Bool {
    isFocused || children.contains(where: \.isDeepFocused)
  }

  /// Resolves which of the children run. See `isSelected`.
  fileprivate func resolvingSelection() -> ExampleNode {
    var node = self
    let candidates = children.filter { !$0.isExcluded }
    let anyFocused = candidates.contains(where: \.isDeepFocused)
    node.children = children.map { child in
      var child = child
      child.isSelected = !child.isExcluded && (!anyFocused || child.isDeepFocused)
      return child
    }
    return node
  }
}

extension ExampleNode: TestElement {
  var description: String { name }
}

// MARK: - Building

/// Lets the node builder get at what is specific to each call type. This is
/// internal, so it isn't a requirement of the public `CallType`.
protocol NodeCallType: CallType {
  static var nodeIsolation: ExampleNode.Isolation { get }
  static var nodeExecution: ExampleNode.Execution { get }
  static func nodeBody(_ callback: Callback) -> ExampleNode.Body
  static func nodeAround(_ callback: AroundCallback) -> ExampleNode.AroundBody
}

extension SyncCall: NodeCallType {
  static var nodeIsolation: ExampleNode.Isolation { .nonisolated }
  static var nodeExecution: ExampleNode.Execution { .sync }
  static func nodeBody(_ callback: @escaping Callback) -> ExampleNode.Body { .sync(callback) }
  static func nodeAround(_ callback: @escaping AroundCallback) -> ExampleNode.AroundBody { .sync(callback) }
}
extension AsyncCall: NodeCallType {
  static var nodeIsolation: ExampleNode.Isolation { .nonisolated }
  static var nodeExecution: ExampleNode.Execution { .async }
  static func nodeBody(_ callback: @escaping Callback) -> ExampleNode.Body { .async(callback) }
  static func nodeAround(_ callback: @escaping AroundCallback) -> ExampleNode.AroundBody { .async(callback) }
}
extension SyncMainCall: NodeCallType {
  static var nodeIsolation: ExampleNode.Isolation { .mainActor }
  static var nodeExecution: ExampleNode.Execution { .sync }
  static func nodeBody(_ callback: @escaping Callback) -> ExampleNode.Body { .syncMain(callback) }
  static func nodeAround(_ callback: @escaping AroundCallback) -> ExampleNode.AroundBody { .syncMain(callback) }
}
extension AsyncMainCall: NodeCallType {
  static var nodeIsolation: ExampleNode.Isolation { .mainActor }
  static var nodeExecution: ExampleNode.Execution { .async }
  static func nodeBody(_ callback: @escaping Callback) -> ExampleNode.Body { .asyncMain(callback) }
  static func nodeAround(_ callback: @escaping AroundCallback) -> ExampleNode.AroundBody { .asyncMain(callback) }
}

/// Elements that can describe themselves as a node, whatever their call type
protocol NodeConvertible {
  var node: ExampleNode { get }
}

extension ExampleGroup: NodeConvertible where Call: NodeCallType {}
extension It: NodeConvertible where Call: NodeCallType {}

extension ExampleGroup where Call: NodeCallType {
  /// The tree of nodes for this group and everything in it
  var node: ExampleNode {
    nodeBeforeSelection.resolvingSelection()
  }

  private var nodeBeforeSelection: ExampleNode {
    ExampleNode(
      kind: .group,
      name: description,
      traits: traits,
      isolation: Call.nodeIsolation,
      execution: Call.nodeExecution,
      body: nil,
      around: nil,
      // An async group can hold sync elements as well as async ones, so this
      // takes whatever call type the element has.
      children: elements.map { element in
        guard let convertible = element as? any NodeConvertible
        else { preconditionFailure("unexpected element type") }
        return convertible.node
      },
      hooks: [
        .beforeAll: beforeAllHooks.map { $0.node(.beforeAll) },
        .aroundEach: aroundEachHooks.map { $0.node },
        .beforeEach: beforeEachHooks.map { $0.node(.beforeEach) },
        .afterEach: afterEachHooks.map { $0.node(.afterEach) },
        .afterAll: afterAllHooks.map { $0.node(.afterAll) },
      ].filter { !$0.value.isEmpty })
  }
}

extension It where Call: NodeCallType {
  var node: ExampleNode {
    ExampleNode(kind: .example,
                name: description,
                traits: traits,
                isolation: Call.nodeIsolation,
                execution: Call.nodeExecution,
                body: Call.nodeBody(block),
                around: nil,
                children: [],
                hooks: [:])
  }
}

extension TestHook where Call: NodeCallType {
  fileprivate func node(_ kind: ExampleNode.HookKind) -> ExampleNode {
    ExampleNode(kind: .hook(kind),
                name: description,
                traits: traits,
                isolation: Call.nodeIsolation,
                execution: Call.nodeExecution,
                body: Call.nodeBody(block),
                around: nil,
                children: [],
                hooks: [:],
                isSelected: !isExcluded)
  }
}

extension AroundEach where Call: NodeCallType {
  fileprivate var node: ExampleNode {
    ExampleNode(kind: .hook(.aroundEach),
                name: description,
                traits: traits,
                isolation: Call.nodeIsolation,
                execution: Call.nodeExecution,
                body: nil,
                around: Call.nodeAround(block),
                children: [],
                hooks: [:],
                isSelected: !isExcluded)
  }
}
