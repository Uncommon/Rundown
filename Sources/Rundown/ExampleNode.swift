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
/// `It`, `TestHook`, `AroundEach` and `AroundEachPeer`, exist to be written
/// against. They are generic over the call type and phase (`BeforeAllPhase`,
/// `ExamplePhase` and so on) so that the compiler enforces the order and
/// structure of a spec: hooks before examples, `afterAll` last, no
/// around hooks after an example, and a main-actor closure only where
/// main-actor elements are allowed. That is also why the DSL functions return
/// them, which makes them public API.
///
/// Once a spec is built, none of that is needed to run it, and the generics
/// get in the way: every traversal repeats for each call type. The node tree is
/// what the built group looks like with the builder's types removed. It is
/// derived from them and never built by hand, and nothing about order is
/// checked here, because by this point the builder has already guaranteed it.
/// Only the call-type split that can't be erased remains (see `Body`).
package struct ExampleNode: Sendable {
  enum Kind: Hashable, Sendable {
    case group
    case example
    case hook(HookKind)
  }

  /// The place of a hook in the lifecycle of its group
  enum HookKind: CaseIterable, Hashable, Sendable {
    case beforeAll, aroundEach, beforeEach, afterEach, aroundEachPeer, beforeEachPeer, afterEachPeer, afterAll
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

  /// The closure of an around hook, which takes the callback to wrap
  enum AroundBody: Sendable {
    case sync(SyncCall.AroundCallback)
    case async(AsyncCall.AroundCallback)
    case syncMain(SyncMainCall.AroundCallback)
    case asyncMain(AsyncMainCall.AroundCallback)
  }

  let kind: Kind
  /// The same text as the `description` of the element, so a hook's includes
  /// its phase, such as "before each peer: name".
  let name: String
  package let declarationLocation: DeclarationLocation?
  package let traits: [any Trait]
  let isolation: Isolation
  let execution: Execution

  /// What running the node does, for examples and non-around hooks
  let body: Body?
  /// The wrapper of an around hook
  let around: AroundBody?

  /// The groups and examples directly inside a group, in order. Empty for
  /// examples and hooks.
  private(set) var children: [ExampleNode]

  /// The hooks declared by a group, in order within each kind. Peer hooks
  /// apply to immediate children, counting a nested group as one peer.
  /// Per-example hooks are accumulated during traversal and run for every
  /// selected descendant example. Empty for examples and hooks.
  private(set) var hooks: [HookKind: [ExampleNode]]

  func hooks(_ kind: HookKind) -> [ExampleNode] {
    hooks[kind] ?? []
  }

  /// Whether the node is selected to run. Selection is resolved when the tree
  /// is built, keeping excluded and unselected nodes to preserve its structure.
  ///
  /// - A node with the `.excluded` trait is not selected.
  /// - If any child of a group has focus outside an excluded subtree, then
  ///   only those children are selected, and the rest are left out.
  /// - Otherwise every non-excluded child is selected.
  ///
  /// Every descendant and hook of an unselected group is also unselected.
  /// The root is selected unless it has the `.excluded` trait.
  private(set) var isSelected: Bool = true

  /// The children that run, in order
  var selectedChildren: [ExampleNode] {
    children.filter(\.isSelected)
  }

  /// The hooks of the given kind that run, in order
  func selectedHooks(_ kind: HookKind) -> [ExampleNode] {
    hooks(kind).filter(\.isSelected)
  }

  package var isGroup: Bool { kind == .group }
  var isExample: Bool { kind == .example }
  package var isAroundHook: Bool { kind == .hook(.aroundEach) || kind == .hook(.aroundEachPeer) }

  var isExcluded: Bool { traits.contains { $0 is ExcludedTrait } }
  var isFocused: Bool { traits.contains { $0 is FocusedTrait } }
  package var isConcurrent: Bool { traits.contains { $0 is ConcurrentTrait } }

  /// Whether this node or a descendant contributes focus. An excluded subtree
  /// never contributes focus, even if it contains focused nodes.
  var isDeepFocused: Bool {
    !isExcluded && (isFocused || children.contains(where: \.isDeepFocused))
  }

  /// Resolves which of the children run. See `isSelected`.
  fileprivate func resolvingSelection() -> ExampleNode {
    guard !isExcluded
    else { return deselectingSubtree() }
    var node = self
    let anyFocused = children.contains(where: \.isDeepFocused)
    node.children = children.map { child in
      if child.isExcluded || (anyFocused && !child.isDeepFocused) {
        return child.deselectingSubtree()
      }
      return child
    }
    return node
  }

  private func deselectingSubtree() -> ExampleNode {
    var node = self
    node.isSelected = false
    node.children = children.map { $0.deselectingSubtree() }
    node.hooks = hooks.mapValues { $0.map { $0.deselectingSubtree() } }
    return node
  }

  /// Finds focused examples and groups that exclusion prevents from running.
  /// Inspect the declared traits even in unselected branches so that focus
  /// hidden by an excluded ancestor can still be diagnosed.
  func excludedFocusPaths(under path: [String] = [], excludedByAncestor: Bool = false) -> [[String]] {
    let path = path + [description]
    let excluded = excludedByAncestor || isExcluded
    var paths = excluded && isFocused ? [path] : []
    for child in children {
      paths += child.excludedFocusPaths(under: path, excludedByAncestor: excluded)
    }
    return paths
  }

  struct SynchronousAroundHook {
    let hook: ExampleNode
    let groups: [ExampleNode]

    var error: SynchronousAroundHookError {
      .init(path: groups.map(\.description) + [hook.description])
    }
  }

  /// Runtime validation follows selection. Explicit conversion checks every
  /// declared hook, since even an excluded sync wrapper cannot be converted.
  func firstSynchronousAroundHook(includingUnselected: Bool = false,
                                  under groups: [ExampleNode] = []) -> SynchronousAroundHook? {
    guard isGroup, includingUnselected || (isSelected && !selectedChildren.isEmpty)
    else { return nil }
    let groups = groups + [self]
    for kind in [HookKind.aroundEachPeer, .aroundEach] {
      for hook in hooks(kind) where includingUnselected || hook.isSelected {
        switch hook.around {
          case .sync, .syncMain:
            return .init(hook: hook, groups: groups)
          default:
            break
        }
      }
    }
    for child in children {
      if let conflict = child.firstSynchronousAroundHook(includingUnselected: includingUnselected, under: groups) {
        return conflict
      }
    }
    return nil
  }
}

extension ExampleNode: TestElement {
  package var description: String { name }
}

#if canImport(Darwin) && compiler(>=6.4)
extension ExampleNode {
  package var indexedSelectedChildren: [(offset: Int, element: ExampleNode)] {
    children.enumerated().filter { $0.element.isSelected }
  }

  package func retainingOnly(_ child: Self) -> Self {
    var node = self
    node.children = [child]
    return node
  }

  package var withoutGroupHooks: Self {
    var node = self
    node.hooks[.beforeAll] = nil
    node.hooks[.afterAll] = nil
    return node
  }
}
#endif

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

// The adapter builds roots from these four call types. The generic node
// builder and its call-type requirements stay internal to Rundown.
extension ExampleGroup where Call == SyncCall {
  package var node: ExampleNode { makeNode() }
}

extension ExampleGroup where Call == AsyncCall {
  package var node: ExampleNode { makeNode() }
}

extension ExampleGroup where Call == SyncMainCall {
  package var node: ExampleNode { makeNode() }
}

extension ExampleGroup where Call == AsyncMainCall {
  package var node: ExampleNode { makeNode() }
}

extension ExampleGroup where Call: NodeCallType {
  /// The tree of nodes for this group and everything in it
  var node: ExampleNode { makeNode() }

  fileprivate func makeNode() -> ExampleNode {
    nodeBeforeSelection.resolvingSelection()
  }

  private var nodeBeforeSelection: ExampleNode {
    ExampleNode(kind: .group,
                name: description,
                declarationLocation: nil,
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
                  .aroundEachPeer: aroundEachPeerHooks.map { $0.node },
                  .beforeEachPeer: beforeEachPeerHooks.map { $0.node(.beforeEachPeer) },
                  .afterEachPeer: afterEachPeerHooks.map { $0.node(.afterEachPeer) },
                  .afterAll: afterAllHooks.map { $0.node(.afterAll) },
                ].filter { !$0.value.isEmpty })
  }
}

extension It where Call: NodeCallType {
  var node: ExampleNode {
    ExampleNode(kind: .example,
                name: description,
                declarationLocation: declarationLocation,
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

extension TestHook where Call: NodeCallType {
  fileprivate func node(_ kind: ExampleNode.HookKind) -> ExampleNode {
    ExampleNode(kind: .hook(kind),
                name: description,
                declarationLocation: declarationLocation,
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

extension AroundEachPeer where Call: NodeCallType {
  fileprivate var node: ExampleNode {
    ExampleNode(kind: .hook(.aroundEachPeer),
                name: description,
                declarationLocation: declarationLocation,
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

extension AroundEach where Call: NodeCallType {
  fileprivate var node: ExampleNode {
    ExampleNode(kind: .hook(.aroundEach),
                name: description,
                declarationLocation: declarationLocation,
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
