import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// This SyntaxRewriter is responsible for finding 'await'
/// expressions and removing the 'await' keyword,
/// leaving only the expression that followed it.
private class AwaitStripper: SyntaxRewriter {
  override func visit(_ node: AwaitExprSyntax) -> ExprSyntax {
    // Get the expression *after* 'await' (e.g., "try service.fetch()")
    let innerExpression = node.expression
    
    // Recurse on that expression in case it has nested awaits
    // (e.g., "myFunc(await otherFunc())")
    let rewrittenInnerExpression = self.rewrite(innerExpression).as(
      ExprSyntax.self
    )!
    
    // Return *just* the rewritten inner expression.
    // This effectively removes the 'await' keyword.
    return rewrittenInnerExpression
  }
  
  override func visit(_ node: FunctionTypeSyntax) -> TypeSyntax {
    let specifiers = node.effectSpecifiers?.with(\.asyncSpecifier, nil)
    return .init(node.with(\.effectSpecifiers, specifiers))
  }
}

private class TypeChangeRewriter: SyntaxRewriter {
  let replacements: [String:String]
  
  init(replacements: [String:String]) {
    self.replacements = replacements
  }
  
  override func visit(_ node: IdentifierTypeSyntax) -> TypeSyntax {
    if let newName = replacements[node.name.text] {
      var newNode = node
      newNode.name = .identifier(newName)
      return TypeSyntax(newNode)
    }
    return super.visit(node)
  }
  
  override func visit(_ node: GenericArgumentSyntax) -> GenericArgumentSyntax {
    if let newName = replacements[node.argument.description] {
      return node.with(\.argument, .init(stringLiteral: newName))
    }
    return super.visit(node)
  }
  
  override func visit(_ node: SameTypeRequirementSyntax) -> SameTypeRequirementSyntax {
    if let newName = replacements[node.rightType.description] {
      return node.with(\.rightType, .init(stringLiteral: newName))
    }
    return super.visit(node)
  }
}

public struct DeAsyncMacro: PeerMacro {
  /// Parses an argument representing an array of types like `[TypeA.self, TypeB.self]`
  /// and returns an array of strings containing the type names: `["TypeA", "TypeB"]`.
  static func parseTypeNames(_ argument: LabeledExprSyntax) -> [String] {
    guard let arrayExpr = argument.expression.as(ArrayExprSyntax.self) else {
      return []
    }
    
    var typeNames: [String] = []
    for element in arrayExpr.elements {
      guard let memberAccess = element.expression.as(MemberAccessExprSyntax.self),
            let baseIdent = memberAccess.base?.as(DeclReferenceExprSyntax.self),
            !baseIdent.baseName.text.isEmpty else {
        return []
      }
      typeNames.append(baseIdent.baseName.text)
    }
    return typeNames
  }
  
  /// Converts the two type list arguments into a dictionary
  static func parseReplacementDictionary(_ node: AttributeSyntax) -> [String:String] {
    guard let arguments = node.arguments,
          arguments.children(viewMode: .all).count == 2
    else { return [:] }
    let names = arguments.children(viewMode: .all)
      .compactMap { $0.as(LabeledExprSyntax.self) }
      .map { parseTypeNames($0) }
    let pairs = zip(names[0], names[1])
    
    return .init(pairs, uniquingKeysWith: { (a, b) in a })
  }
  
  static func filterDisfavoredOverload(_ attributes: AttributeListSyntax) -> AttributeListSyntax {
    attributes.filter { return $0.trimmedDescription != "@_disfavoredOverload" }
  }
  
  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard var funcDecl = declaration.as(FunctionDeclSyntax.self)
    else {
      throw MacroError.message("@DeAsync can only be applied to functions.")
    }
    
    funcDecl.attributes = filterDisfavoredOverload(funcDecl.attributes)
    
    let defaultReplacements = node.attributeName.description == "DeAsyncRD" ? ["AsyncCall":"SyncCall"] : [:]
    let replacements = parseReplacementDictionary(node).merging(defaultReplacements, uniquingKeysWith: { (a, b) in a })
    let signature = funcDecl.signature
    let effects = signature.effectSpecifiers
    
    var newEffects = effects
    newEffects?.asyncSpecifier = nil  // Strip 'async'
    
    if newEffects?.asyncSpecifier == nil
        && newEffects?.throwsClause?.throwsSpecifier == nil
    {
      newEffects = nil
    }
    
    let awaitStripper = AwaitStripper()
    let typeChangeRewriter = TypeChangeRewriter(replacements: replacements)
    var convertedSignature = replacements.isEmpty ? signature : typeChangeRewriter.rewrite(signature).as(FunctionSignatureSyntax.self)!
    
    convertedSignature = awaitStripper.rewrite(convertedSignature).as(FunctionSignatureSyntax.self)!
      .with(\.effectSpecifiers, newEffects)
    
    let whereClause = replacements.isEmpty ? nil : funcDecl.genericWhereClause.map {
      typeChangeRewriter.rewrite($0).as(GenericWhereClauseSyntax.self)!
    }
    
    guard let body = funcDecl.body else {
      throw MacroError.message(
        "@DeAsync cannot be applied to a function with no body (e.g., a protocol requirement)."
      )
    }
    
    let newBody = awaitStripper.rewrite(body).as(CodeBlockSyntax.self)!
    
    let macroBaseName =
    node.attributeName.trimmedDescription
      .split(separator: ".").last
      .map(String.init) ?? "AddSyncPeer"
    
    let newAttributes = funcDecl.attributes.filter {
      guard case .attribute(let attr) = $0 else { return true }
      let attrBaseName = attr.attributeName.trimmedDescription
        .split(separator: ".").last
        .map(String.init)
      return attrBaseName != macroBaseName
    }
    
    let newFunc = funcDecl
      .with(\.attributes, newAttributes)
      .with(\.signature, convertedSignature)
      .with(\.genericWhereClause, whereClause)
      .with(\.body, newBody)
    
    return [DeclSyntax(newFunc)]
  }
}

enum MacroError: Error, CustomStringConvertible {
  case message(String)
  var description: String {
    switch self {
    case .message(let text):
      return text
    }
  }
}

