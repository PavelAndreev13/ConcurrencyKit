import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import Foundation

public struct AsyncBridgeMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {

        guard let funcDecl = declaration.as(FunctionDeclSyntax.self) else {
            throw MacroError.onlyApplicableToFunctions
        }

        let funcName = funcDecl.name.text

        guard let completionParam = funcDecl.signature.parameterClause.parameters.last,
              let paramName = completionParam.firstName.text as String?,
              paramName.contains("completion") else {
            throw MacroError.noCompletionHandlerFound
        }

        let typeSyntax = completionParam.type
        guard let functionType = typeSyntax.as(AttributedTypeSyntax.self)?.baseType.as(FunctionTypeSyntax.self) ??
                                 typeSyntax.as(FunctionTypeSyntax.self) else {
            throw MacroError.unsupportedCompletionFormat
        }

        let closureParams = Array(functionType.parameters)

        var generatedAsyncReturnType = "Void"
        var generatedBody = ""

        if closureParams.count == 2 {
            // Pattern 1: (SuccessType?, Error?) -> Void
            // Strip the optional "?" to get the clean return type (e.g. "User?" → "User")
            let rawTypeStr = closureParams[0].type.description
            let cleanTypeStr = rawTypeStr.replacingOccurrences(of: "?", with: "").trimmingCharacters(in: .whitespaces)

            generatedAsyncReturnType = cleanTypeStr

            // Generate the async body for a function that returns a value
            generatedBody = """
            try await withCheckedThrowingContinuation { continuation in
                self.\(funcName) { result, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let result = result {
                        continuation.resume(returning: result)
                    } else {
                        let unknownError = NSError(domain: "AsyncBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error or missing data"])
                        continuation.resume(throwing: unknownError)
                    }
                }
            }
            """

        } else if closureParams.count == 1 {
            // Pattern 2: (Error?) -> Void
            // The function returns Void — just wait for completion and forward any error
            generatedBody = """
            try await withCheckedThrowingContinuation { continuation in
                self.\(funcName) { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
            """

        } else {
            throw MacroError.unsupportedCompletionFormat
        }

        // Assemble the full async function declaration
        let asyncFuncString = """
        func \(funcName)() async throws -> \(generatedAsyncReturnType) {
            \(generatedBody)
        }
        """

        return [DeclSyntax(stringLiteral: asyncFuncString)]
    }
}

enum MacroError: Error, CustomStringConvertible {
    case onlyApplicableToFunctions
    case noCompletionHandlerFound
    case unsupportedCompletionFormat

    var description: String {
        switch self {
        case .onlyApplicableToFunctions:
            return "@AsyncBridge can only be applied to functions."
        case .noCompletionHandlerFound:
            return "The last parameter must be named 'completion' or contain that word."
        case .unsupportedCompletionFormat:
            return "Only closures of the form (T?, Error?) -> Void or (Error?) -> Void are supported."
        }
    }
}

public struct StringifyMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) -> ExprSyntax {
        guard let argument = node.arguments.first?.expression else {
            fatalError("compiler bug: the macro does not have any arguments")
        }

        return "(\(argument), \(literal: argument.description))"
    }
}

@main
struct ConcurrencyKitPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        StringifyMacro.self,
        AsyncBridgeMacro.self,
    ]
}
