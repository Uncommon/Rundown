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
    let rewrittenInnerExpression = self.rewrite(innerExpression).as(ExprSyntax.self)!
    
    // Return *just* the rewritten inner expression.
    // This effectively removes the 'await' keyword.
    return rewrittenInnerExpression.with(\.leadingTrivia, node.leadingTrivia + rewrittenInnerExpression.leadingTrivia)
  }
  
  override func visit(_ node: FunctionTypeSyntax) -> TypeSyntax {
    let specifiers = node.effectSpecifiers?.with(\.asyncSpecifier, nil)
    return .init(node.with(\.effectSpecifiers, specifiers))
  }
}

private func typeKey(_ type: some SyntaxProtocol) -> String {
  type.tokens(viewMode: .sourceAccurate).map(\.text).joined()
}

private class TypeChangeRewriter: SyntaxRewriter {
  let replacements: [String:String]
  
  init(replacements: [String:String]) {
    self.replacements = replacements
  }
  
  override func visitAny(_ node: Syntax) -> Syntax? {
    guard let type = node.as(TypeSyntax.self),
          let replacement = replacements[typeKey(type)]
    else { return nil }
    return Syntax(TypeSyntax(stringLiteral: replacement)
      .with(\.leadingTrivia, type.leadingTrivia)
      .with(\.trailingTrivia, type.trailingTrivia))
  }
}

// Duplicated here to avoid circular dependency
public enum StripSendable: String {
  case none, parameters, function, all
  
  var shouldStripParameters: Bool { self == .parameters || self == .all }
  var shouldStripFunction: Bool { self == .function || self == .all }
}

public struct DeAsyncMacro: PeerMacro {
  /// Reads literal metatypes, including qualified and compound types.
  static func parseTypeNames(_ argument: LabeledExprSyntax) throws -> [String] {
    guard let arrayExpr = argument.expression.as(ArrayExprSyntax.self)
    else {
      throw MacroError.message("@DeAsync replacement arguments must be array literals of types such as [Value.self].")
    }
    
    var typeNames: [String] = []
    for element in arrayExpr.elements {
      guard let memberAccess = element.expression.as(MemberAccessExprSyntax.self),
            memberAccess.declName.baseName.text == "self",
            let base = memberAccess.base
      else {
        throw MacroError.message("@DeAsync replacement types must use Type.self syntax.")
      }
      let type = TypeSyntax(stringLiteral: base.trimmedDescription)
      guard !type.hasError
      else {
        throw MacroError.message("@DeAsync replacement types must use Type.self syntax.")
      }
      typeNames.append(type.trimmedDescription)
    }
    return typeNames
  }
  
  /// Converts the two type list arguments into a dictionary
  static func parseReplacementDictionary(_ node: AttributeSyntax) throws -> [String:String] {
    guard let arguments = node.arguments?.as(LabeledExprListSyntax.self)
    else { return [:] }
    let oldNames = try arguments.first { $0.label?.text == "replacing" }.map(parseTypeNames) ?? []
    let newNames = try arguments.first { $0.label?.text == "with" }.map(parseTypeNames) ?? []
    guard oldNames.count == newNames.count
    else {
      throw MacroError.message("@DeAsync requires 'replacing' and 'with' to contain the same number of types.")
    }
    let keys = oldNames.map { typeKey(TypeSyntax(stringLiteral: $0)) }
    let pairs = zip(keys, newNames)
    
    return .init(pairs, uniquingKeysWith: { (a, b) in a })
  }
  
  /// Returns the requested case, or `.none` when the argument is omitted.
  static func stripSendableParameterValue(_ node: AttributeSyntax) throws -> StripSendable {
    guard let argument = node.arguments?.as(LabeledExprListSyntax.self)?
      .first(where: { $0.label?.text == "stripSendable" })
    else {
      return .none
    }
    guard let memberAccess = argument.expression.as(MemberAccessExprSyntax.self),
          let strip = StripSendable(rawValue: memberAccess.declName.baseName.text)
    else {
      throw MacroError.message("@DeAsync requires 'stripSendable' to be .none, .parameters, .function, or .all.")
    }
    return strip
  }
  
  /// Removes all '@Sendable' effect specifiers from closure parameter types in the function signature.
  static func stripSendable(_ funcDecl: FunctionSignatureSyntax) -> FunctionSignatureSyntax {
    let newParameters = funcDecl.parameterClause.parameters.map { param -> FunctionParameterSyntax in
      if let type = param.type.as(AttributedTypeSyntax.self) {
        let attributes = remove("@Sendable", from: type.attributes)
        
        return param.with(\.type, .init(type.with(\.attributes, attributes)))
      }
      return param
    }
    let newParamClause = funcDecl.parameterClause.with(\.parameters, .init(newParameters))
    
    return funcDecl.with(\.parameterClause, newParamClause)
  }
  
  static func filterDisfavoredOverload(_ attributes: AttributeListSyntax) -> AttributeListSyntax {
    remove("@_disfavoredOverload", from: attributes)
  }

  static func remove(_ name: String, from attributes: AttributeListSyntax) -> AttributeListSyntax {
    attributes.filter { return $0.trimmedDescription != name }
  }

  public static func expansion(of node: AttributeSyntax,
                               providingPeersOf declaration: some DeclSyntaxProtocol,
                               in context: some MacroExpansionContext) throws -> [DeclSyntax] {
    guard var funcDecl = declaration.as(FunctionDeclSyntax.self)
    else {
      throw MacroError.message("@DeAsync can only be applied to functions.")
    }
    
    let strip = try stripSendableParameterValue(node)
    
    funcDecl.attributes = filterDisfavoredOverload(funcDecl.attributes)
    if strip.shouldStripFunction {
      funcDecl.attributes = remove("@Sendable", from: funcDecl.attributes)
    }
    if strip.shouldStripParameters {
      funcDecl.signature = stripSendable(funcDecl.signature)
    }
    
    let macroBaseName = node.attributeName.trimmedDescription.split(separator: ".").last.map(String.init) ?? "DeAsync"
    let defaultReplacements = macroBaseName == "DeAsyncRD" ? ["AsyncCall":"SyncCall", "AsyncMainCall":"SyncMainCall"] : [:]
    let replacements = try parseReplacementDictionary(node).merging(defaultReplacements, uniquingKeysWith: { (a, b) in a })
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
    
    let whereClause = funcDecl.genericWhereClause.map {
      typeChangeRewriter.rewrite($0).as(GenericWhereClauseSyntax.self)!
    }
    
    guard let body = funcDecl.body
    else {
      throw MacroError.message("@DeAsync cannot be applied to a function with no body (e.g., a protocol requirement).")
    }
    
    let newBody = awaitStripper.rewrite(body).as(CodeBlockSyntax.self)!
    
    let newAttributes = funcDecl.attributes.filter {
      guard case .attribute(let attr) = $0
      else { return true }
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

