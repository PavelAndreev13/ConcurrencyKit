import Testing
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Foundation
import ConcurrencyKit

#if canImport(ConcurrencyKitMacros)
import ConcurrencyKitMacros

private let testMacros: [String: Macro.Type] = [
    "AsyncBridge": AsyncBridgeMacro.self,
]
#endif

// MARK: - TaskVault Tests

@Suite("TaskVault")
struct TaskVaultTests {

    // MARK: Store

    @Test("store() returns a unique UUID per task")
    func storeReturnsUniqueIDs() async {
        let vault = TaskVault()
        let task1 = Task<Void, Never> { try? await Task.sleep(for: .seconds(100)) }
        let task2 = Task<Void, Never> { try? await Task.sleep(for: .seconds(100)) }
        defer { task1.cancel(); task2.cancel() }

        let id1 = await vault.store(task1)
        let id2 = await vault.store(task2)

        #expect(id1 != id2)
    }

    // MARK: Cancel by ID

    @Test("cancel(id:) cancels the matching task")
    func cancelByID() async {
        let vault = TaskVault()
        let task = Task<Void, Never> { try? await Task.sleep(for: .seconds(100)) }

        let id = await vault.store(task)
        await vault.cancel(id: id)

        #expect(task.isCancelled)
    }

    @Test("cancel(id:) does not affect other stored tasks")
    func cancelByIDLeavesOtherTasksRunning() async {
        let vault = TaskVault()
        let task1 = Task<Void, Never> { try? await Task.sleep(for: .seconds(100)) }
        let task2 = Task<Void, Never> { try? await Task.sleep(for: .seconds(100)) }
        defer { task1.cancel(); task2.cancel() }

        let id1 = await vault.store(task1)
        await vault.store(task2)
        await vault.cancel(id: id1)

        #expect(task1.isCancelled)
        #expect(!task2.isCancelled)
    }

    @Test("cancel(id:) with unknown UUID is a no-op")
    func cancelUnknownIDIsNoOp() async {
        let vault = TaskVault()
        // Should not crash or throw
        await vault.cancel(id: UUID())
    }

    // MARK: Cancel All

    @Test("cancelAll() cancels every stored task")
    func cancelAll() async {
        let vault = TaskVault()
        let task1 = Task<Void, Never> { try? await Task.sleep(for: .seconds(100)) }
        let task2 = Task<Void, Never> { try? await Task.sleep(for: .seconds(100)) }
        let task3 = Task<Void, Never> { try? await Task.sleep(for: .seconds(100)) }

        await vault.store(task1)
        await vault.store(task2)
        await vault.store(task3)
        await vault.cancelAll()

        #expect(task1.isCancelled)
        #expect(task2.isCancelled)
        #expect(task3.isCancelled)
    }

    @Test("cancelAll() on empty vault is a no-op")
    func cancelAllOnEmptyVault() async {
        let vault = TaskVault()
        // Should not crash or throw
        await vault.cancelAll()
    }

    // MARK: Convenience store(in:)

    @Test("store(in:) convenience stores task and returns self")
    func storeConvenienceReturnsSelf() async {
        let vault = TaskVault()
        let task = Task<Void, Never> { try? await Task.sleep(for: .seconds(100)) }

        let returned = await task.store(in: vault)
        defer { returned.cancel() }

        #expect(returned == task)
    }

    @Test("store(in:) task is cancelled by cancelAll()")
    func storeConvenienceCancelledByVault() async {
        let vault = TaskVault()
        let task = Task<Void, Never> { try? await Task.sleep(for: .seconds(100)) }

        await task.store(in: vault)
        await vault.cancelAll()

        #expect(task.isCancelled)
    }
}

// MARK: - AsyncBridge Macro Tests

@Suite("AsyncBridge Macro")
struct AsyncBridgeMacroExpansionTests {

    // MARK: Expansion — (T?, Error?) -> Void

    @Test("Expands (T?, Error?) -> Void into async throws T")
    func expandsDataAndError() {
        #if canImport(ConcurrencyKitMacros)
        assertMacroExpansion(
            """
            @AsyncBridge
            func fetchUser(id: Int, completion: @escaping (User?, Error?) -> Void) {
                // network code
            }
            """,
            expandedSource: """
            func fetchUser(id: Int, completion: @escaping (User?, Error?) -> Void) {
                // network code
            }

            func fetchUser() async throws -> User {
                try await withCheckedThrowingContinuation { continuation in
                    self.fetchUser { result, error in
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
            }
            """,
            macros: testMacros
        )
        #endif
    }

    // MARK: Expansion — (Error?) -> Void

    @Test("Expands (Error?) -> Void into async throws Void")
    func expandsErrorOnly() {
        #if canImport(ConcurrencyKitMacros)
        assertMacroExpansion(
            """
            @AsyncBridge
            func saveContext(completion: @escaping (Error?) -> Void) {
                // save code
            }
            """,
            expandedSource: """
            func saveContext(completion: @escaping (Error?) -> Void) {
                // save code
            }

            func saveContext() async throws -> Void {
                try await withCheckedThrowingContinuation { continuation in
                    self.saveContext { error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: ())
                        }
                    }
                }
            }
            """,
            macros: testMacros
        )
        #endif
    }

    // MARK: Expansion — parameter named "onCompletion"

    @Test("Recognises completion param whose name contains 'completion'")
    func expandsCustomCompletionParamName() {
        #if canImport(ConcurrencyKitMacros)
        assertMacroExpansion(
            """
            @AsyncBridge
            func load(onCompletion: @escaping (Error?) -> Void) {
            }
            """,
            expandedSource: """
            func load(onCompletion: @escaping (Error?) -> Void) {
            }

            func load() async throws -> Void {
                try await withCheckedThrowingContinuation { continuation in
                    self.load { error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: ())
                        }
                    }
                }
            }
            """,
            macros: testMacros
        )
        #endif
    }

    // MARK: Diagnostics

    @Test("Emits error when no completion parameter is present")
    func diagnosticNoCompletion() {
        #if canImport(ConcurrencyKitMacros)
        assertMacroExpansion(
            """
            @AsyncBridge
            func doSomethingSync() {
                print("Hello")
            }
            """,
            expandedSource: """
            func doSomethingSync() {
                print("Hello")
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "The last parameter must be named 'completion' or contain that word.",
                    line: 1, column: 1
                ),
            ],
            macros: testMacros
        )
        #endif
    }

    @Test("Emits error when applied to a non-function declaration")
    func diagnosticNonFunction() {
        #if canImport(ConcurrencyKitMacros)
        assertMacroExpansion(
            """
            @AsyncBridge
            var someProperty: Int = 0
            """,
            expandedSource: """
            var someProperty: Int = 0
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@AsyncBridge can only be applied to functions.",
                    line: 1, column: 1
                ),
            ],
            macros: testMacros
        )
        #endif
    }

    @Test("Emits error when completion closure has unsupported arity")
    func diagnosticUnsupportedArity() {
        #if canImport(ConcurrencyKitMacros)
        assertMacroExpansion(
            """
            @AsyncBridge
            func fetch(completion: @escaping (String?, Int?, Error?) -> Void) {
            }
            """,
            expandedSource: """
            func fetch(completion: @escaping (String?, Int?, Error?) -> Void) {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Only closures of the form (T?, Error?) -> Void or (Error?) -> Void are supported.",
                    line: 1, column: 1
                ),
            ],
            macros: testMacros
        )
        #endif
    }
}
