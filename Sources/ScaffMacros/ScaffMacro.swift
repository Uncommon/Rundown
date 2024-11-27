import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct TestExampleMacro: BodyMacro {
  public static func expansion(of node: AttributeSyntax,
                               providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
                               in context: some MacroExpansionContext) throws
  -> [CodeBlockItemSyntax] {
    guard let function = declaration.as(FunctionDeclSyntax.self)
    else { return [] }
    let name = function.name.text.droppingPrefix("test")
    // Assume that if it's in a class, it must be running under XCTestCase
    let execute = context.lexicalContext.first?.as(ClassDeclSyntax.self) == nil
      ? """
        let run = ExampleRun()
        try _test.execute(in: run)
        """
      : """
        try execute(_test)
        """

    let body = CodeBlockItemSyntax(stringLiteral:
      """
      let _test = Describe("\(name)") {\(function.body?.statements.description ?? "")
      }
      \(execute)
      """)

    // If it's Swift Testing:
    // - take the root element and gather the list of spec names/identifiers
    // - create a Test using __function() that treats each spec as a test case

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
