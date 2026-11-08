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

    return [
      """
      @used
      @section("__DATA_CONST,__swift5_tests")
      private static let __rundownSpecRecord: RundownSwiftTesting.SpecRegistration.Record = (
        0x74657374, 0,
        { outValue, type, _, _ in
          RundownSwiftTesting.SpecRegistration.store(
            \(spec.name.trimmed).self,
            sourceLocation: .init(fileID: \(fileID.file), filePath: \(filePath.file),
                                  line: \(fileID.line), column: \(fileID.column)),
            into: outValue, asTypeAt: type
          )
        },
        0, 0
      )
      """,
    ]
  }
}
