import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct DiscoverySpecMacro: MemberMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let spec = declaration.as(StructDeclSyntax.self), spec.genericParameterClause == nil else {
      throw MacroExpansionErrorMessage("@Spec requires a non-generic struct")
    }
    guard let fileID = context.location(of: spec.name, at: .afterLeadingTrivia, filePathMode: .fileID),
          let filePath = context.location(of: spec.name, at: .afterLeadingTrivia, filePathMode: .filePath) else {
      throw MacroExpansionErrorMessage("@Spec requires a source location for discovery")
    }
    let unit = node.arguments?.as(LabeledExprListSyntax.self)?.first?.expression

    func record(_ name: String, context: Int, store: String, arguments: String = "") -> DeclSyntax {
      """
      @used
      @section("__DATA_CONST,__swift5_tests")
      private static let \(raw: name): RundownSwiftTesting._SpecRegistration.Record = (
        0x74657374, 0,
        { outValue, type, _, _ in
          RundownSwiftTesting._SpecRegistration.\(raw: store)(
            \(spec.name.trimmed).self,
            \(raw: arguments)
            sourceLocation: .init(fileID: \(fileID.file), filePath: \(filePath.file),
                                  line: \(fileID.line), column: \(fileID.column)),
            into: outValue, asTypeAt: type
          )
        },
        \(raw: context), 0
      )
      """
    }

    let arguments = unit.map { "unit: \($0.trimmed)," } ?? ""
    let test = record("__rundownSpecRecord", context: 2, store: "store", arguments: arguments)
    // A native @Suite already emits a record for this suite ID.
    if spec.attributes.contains(where: { $0.as(AttributeSyntax.self)?.unqualifiedName == "Suite" }) {
      return [test]
    }
    return [test, record("__rundownSuiteRecord", context: 1, store: "storeSuite")]
  }
}

extension DiscoverySpecMacro: ExtensionMacro {
  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    guard !protocols.isEmpty else { return [] }
    return [try ExtensionDeclSyntax("extension \(type.trimmed): RundownSwiftTesting.Spec {}")]
  }
}

extension DiscoverySpecMacro: MemberAttributeMacro {
  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingAttributesFor member: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [AttributeSyntax] {
    guard let property = member.as(VariableDeclSyntax.self),
          !property.modifiers.contains(where: { $0.name.text == "static" }),
          property.bindings.count == 1, let binding = property.bindings.first,
          binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "spec",
          let accessors = binding.accessorBlock?.accessors else { return [] }

    let hasBuilder = property.attributes.contains { $0.as(AttributeSyntax.self)?.unqualifiedName == "ExampleBuilder" }
    guard !hasBuilder else { return [] }

    let statements = accessors.as(CodeBlockItemListSyntax.self)
      ?? accessors.as(AccessorDeclListSyntax.self)?
        .first(where: { $0.accessorSpecifier.text == "get" })?.body?.statements
    guard let statements else { return [] }

    // The compiler doesn't infer the builder from the generated conformance.
    // As with an inferred builder, an explicit getter return opts out.
    let returns = GetterReturnFinder(viewMode: .sourceAccurate)
    returns.walk(statements)
    guard !returns.found else { return [] }
    return ["@Rundown.ExampleBuilder<Rundown.AsyncCall>"]
  }
}

private extension AttributeSyntax {
  var unqualifiedName: String? {
    attributeName.as(IdentifierTypeSyntax.self)?.name.text ?? attributeName.as(MemberTypeSyntax.self)?.name.text
  }
}

private final class GetterReturnFinder: SyntaxVisitor {
  private(set) var found = false

  override func visit(_ node: ReturnStmtSyntax) -> SyntaxVisitorContinueKind {
    found = true
    return .skipChildren
  }

  override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
    .skipChildren
  }

  override func visit(_ node: CodeBlockItemSyntax) -> SyntaxVisitorContinueKind {
    if case .decl = node.item { return .skipChildren }
    return found ? .skipChildren : .visitChildren
  }
}
