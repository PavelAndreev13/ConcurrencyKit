# ConcurrencyKit

[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2013%20%7C%20macOS%2010.15-lightgray.svg)]()
[![License](https://img.shields.io/badge/License-MIT-blue.svg)]()

**Painless Swift 6 strict concurrency and legacy code migration.**

ConcurrencyKit is a lightweight Swift library with two tools that make your transition to Swift 6 safe and fast:

- **`TaskVault`** — a thread-safe actor for automatic `Task` lifecycle management.
- **`@AsyncBridge`** — a Swift macro that generates `async throws` wrappers over legacy completion-handler methods.

---

## Installation

Add the package via Xcode (**File → Add Package Dependencies…**) or directly in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/PavelAndreev13/ConcurrencyKit.git", from: "1.0.0")
],
targets: [
    .target(name: "YourTarget", dependencies: ["ConcurrencyKit"])
]
```

---

## TaskVault

`TaskVault` is an `actor` that stores and cancels `Task` instances — analogous to `DisposeBag` in RxSwift, but built natively for Swift 6.

### Storing tasks

```swift
let vault = TaskVault()

// Store a task manually and keep the ID for later cancellation
let id = await vault.store(
    Task {
        await loadData()
    }
)

// Or use the fluent convenience API
Task {
    await processData()
}
.store(in: vault)  // returns the original Task so you can chain further
```

### Cancelling tasks

```swift
// Cancel a specific task by its ID
await vault.cancel(id: id)

// Cancel every task stored in the vault
await vault.cancelAll()
```

### Automatic cleanup on deinit

When a `TaskVault` instance is deallocated, it automatically cancels all stored tasks — no manual cleanup needed.

```swift
// ViewModel example
@MainActor
final class ProfileViewModel: ObservableObject {
    private let vault = TaskVault()

    func loadProfile(userID: String) {
        Task {
            await fetchProfile(userID: userID)
        }
        .store(in: vault)
    }

    // All tasks are cancelled automatically when the ViewModel is deallocated
}
```

---

## @AsyncBridge

`@AsyncBridge` is a peer macro that generates a modern `async throws` counterpart for any method that uses a completion handler. It supports two closure patterns.

### Pattern 1 — `(Result?, Error?) -> Void`

```swift
class NetworkService {

    // Existing legacy method
    @AsyncBridge
    func fetchUser(id: Int, completion: @escaping (User?, Error?) -> Void) {
        URLSession.shared.dataTask(with: makeRequest(id: id)) { data, _, error in
            // ...
            completion(user, error)
        }.resume()
    }

    // @AsyncBridge generates this automatically:
    //
    // func fetchUser() async throws -> User {
    //     try await withCheckedThrowingContinuation { continuation in
    //         self.fetchUser { result, error in
    //             if let error = error {
    //                 continuation.resume(throwing: error)
    //             } else if let result = result {
    //                 continuation.resume(returning: result)
    //             } else {
    //                 continuation.resume(throwing: NSError(...))
    //             }
    //         }
    //     }
    // }
}

// Call site — clean Swift 6 async/await
let user = try await service.fetchUser()
```

### Pattern 2 — `(Error?) -> Void`

```swift
class DatabaseService {

    // Existing legacy method
    @AsyncBridge
    func saveContext(completion: @escaping (Error?) -> Void) {
        context.save { error in
            completion(error)
        }
    }

    // @AsyncBridge generates this automatically:
    //
    // func saveContext() async throws -> Void {
    //     try await withCheckedThrowingContinuation { continuation in
    //         self.saveContext { error in
    //             if let error = error {
    //                 continuation.resume(throwing: error)
    //             } else {
    //                 continuation.resume(returning: ())
    //             }
    //         }
    //     }
    // }
}

// Call site
try await db.saveContext()
```

### Combining both tools

```swift
@MainActor
final class UserViewModel: ObservableObject {
    @Published var user: User?
    private let vault = TaskVault()

    func load(userID: Int) {
        Task {
            user = try await networkService.fetchUser(id: userID)
        }
        .store(in: vault)
    }
}
```

---

## Requirements

| Platform   | Minimum version |
|------------|-----------------|
| iOS        | 13.0            |
| macOS      | 10.15           |
| tvOS       | 13.0            |
| watchOS    | 6.0             |
| Swift      | 6.0             |
