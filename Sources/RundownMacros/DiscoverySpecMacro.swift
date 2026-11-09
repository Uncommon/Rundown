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
    let unit = node.arguments?.as(LabeledExprListSyntax.self)?.first?.expression ?? ".topLevel"

    return [
      """
      @used
      @section("__DATA_CONST,__swift5_tests")
      private static let __rundownSpecRecord: RundownSwiftTesting.SpecRegistration.Record = (
        0x74657374, 0,
        { outValue, type, _, _ in
          RundownSwiftTesting.SpecRegistration.store(
            \(spec.name.trimmed).self,
            unit: \(unit),
            sourceLocation: .init(fileID: \(fileID.file), filePath: \(filePath.file),
                                  line: \(fileID.line), column: \(fileID.column)),
            into: outValue, asTypeAt: type
          )
        },
        0b10, 0
      )
      """,
    ]
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

    let hasBuilder = property.attributes.contains { element in
      guard let name = element.as(AttributeSyntax.self)?.attributeName else { return false }
      return name.as(IdentifierTypeSyntax.self)?.name.text == "ExampleBuilder"
        || name.as(MemberTypeSyntax.self)?.name.text == "ExampleBuilder"
    }
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
