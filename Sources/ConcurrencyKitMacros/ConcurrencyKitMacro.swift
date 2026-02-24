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
            
            let allParams = Array(funcDecl.signature.parameterClause.parameters)
            
            guard let completionParam = allParams.last,
                  let paramName = completionParam.firstName.text as String?,
                  paramName.contains("completion") else {
                throw MacroError.noCompletionHandlerFound
            }
            
          
            let paramsWithoutCompletion = allParams.dropLast()
            
            var asyncParams: [String] = []
            var callArgs: [String] = []
            
            for param in paramsWithoutCompletion {
                // Saving original param
                asyncParams.append(param.trimmedDescription)
                
                // Grab arguments for original arguments
                let firstName = param.firstName.text
                let secondName = param.secondName?.text
                
                if firstName == "_" {
                    // If label is hidden (example: _ id: String), call it via variable: id
                    callArgs.append("\(secondName ?? "")")
                } else {
                    // If have label (example: with id: String -> with: id, or userID: String -> userID: userID)
                    let variableName = secondName ?? firstName
                    callArgs.append("\(firstName): \(variableName)")
                }
            }
            
            let asyncSignature = asyncParams.joined(separator: ", ")
            let callArguments = callArgs.joined(separator: ", ")
            
            let callPrefix = callArguments.isEmpty ? "self.\(funcName)" : "self.\(funcName)(\(callArguments))"
            // -----------------------------------------------------------
            
            let typeSyntax = completionParam.type
            guard let functionType = typeSyntax.as(AttributedTypeSyntax.self)?.baseType.as(FunctionTypeSyntax.self) ??
                                     typeSyntax.as(FunctionTypeSyntax.self) else {
                throw MacroError.unsupportedCompletionFormat
            }
            
            let closureParams = Array(functionType.parameters)
            
            var generatedAsyncReturnType = "Void"
            var generatedBody = ""
            
            if closureParams.count == 2 {
                // ПАТТЕРН 1: (SuccessType?, Error?)
                let rawTypeStr = closureParams[0].type.description
                let cleanTypeStr = rawTypeStr.replacingOccurrences(of: "?", with: "").trimmingCharacters(in: .whitespaces)
                generatedAsyncReturnType = cleanTypeStr
                
                generatedBody = """
                try await withCheckedThrowingContinuation { continuation in
                    \(callPrefix) { result, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else if let result = result {
                            continuation.resume(returning: result)
                        } else {
                            let unknownError = NSError(domain: "AsyncBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"])
                            continuation.resume(throwing: unknownError)
                        }
                    }
                }
                """
                
            } else if closureParams.count == 1 {
                let paramType = closureParams[0].type
                let rawTypeStr = paramType.description.trimmingCharacters(in: .whitespaces)
                
                if rawTypeStr.hasPrefix("Result<") {
                    if let identifierType = paramType.as(IdentifierTypeSyntax.self),
                       identifierType.name.text == "Result",
                       let genericArgs = identifierType.genericArgumentClause?.arguments,
                       let successType = genericArgs.first?.argument {
                        
                        generatedAsyncReturnType = successType.description.trimmingCharacters(in: .whitespaces)
                        
                        generatedBody = """
                        try await withCheckedThrowingContinuation { continuation in
                            \(callPrefix) { result in
                                continuation.resume(with: result)
                            }
                        }
                        """
                    } else {
                        throw MacroError.unsupportedCompletionFormat
                    }
                } else {
                    generatedBody = """
                    try await withCheckedThrowingContinuation { continuation in
                        \(callPrefix) { error in
                            if let error = error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume(returning: ())
                            }
                        }
                    }
                    """
                }
            } else {
                throw MacroError.unsupportedCompletionFormat
            }
            
            let isProtocolRequirement = funcDecl.body == nil
                    
            let asyncFuncString: String
                    
            if isProtocolRequirement {
                
                asyncFuncString = """
                    func \(funcName)(\(asyncSignature)) async throws -> \(generatedAsyncReturnType)
                    """
            } else {
                asyncFuncString = """
                func \(funcName)(\(asyncSignature)) async throws -> \(generatedAsyncReturnType) {
                \(generatedBody)
                }
                """
            }
                    
            return [DeclSyntax(stringLiteral: asyncFuncString)]
        }
}

enum MacroError: Error, CustomStringConvertible {
    case onlyApplicableToFunctions
    case noCompletionHandlerFound
    case unsupportedCompletionFormat
    
    var description: String {
        switch self {
        case .onlyApplicableToFunctions: return "@AsyncBridge use only for methods/functions"
        case .noCompletionHandlerFound: return "last param must be called 'completion' or contain this word."
        case .unsupportedCompletionFormat: return "Support only closures with signature (T?, Error?) -> Void or (Error?) -> Void."
        }
    }
}

@main
struct ConcurrencyKitPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        AsyncBridgeMacro.self
    ]
}
