import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct TestExampleMacro: BodyMacro {
  public static func expansion(of node: AttributeSyntax,
                               providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
                               in context: some MacroExpansionContext) throws
  -> [CodeBlockItemSyntax] {
    // strip "test" from the function name
    // let [name] = Describe("Name") { [body content] }
    // try [name].execute()
    guard let function = declaration.as(FunctionDeclSyntax.self)
    else { return [] }
    let name = function.name.text.droppingPrefix("test")
    let body = CodeBlockItemSyntax(stringLiteral: """
    // TODO: remove the extra line at the start of the block
    let _test = Describe("\(name)") {
      \(function.body?.statements.description ?? "")
    }
    try _test.execute()
    """)
    
    return [body]
  }
}

@main
struct ScaffPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    TestExampleMacro.self,
  ]
}

extension String
{
  /// Returns the string with the given prefix removed, or returns the string
  /// unchanged if the prefix does not match.
  func droppingPrefix(_ prefix: String) -> String
  {
    guard hasPrefix(prefix)
    else { return self }
    
    return String(self[prefix.endIndex...])
  }
}
