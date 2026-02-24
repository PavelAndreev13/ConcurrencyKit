# ConcurrencyKit 🚀

[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2015%20%7C%20macOS%2012-lightgray.svg)]()
[![License](https://img.shields.io/badge/License-MIT-blue.svg)]()

**Painless Swift 6 Strict Concurrency & Legacy Code Migration.**

ConcurrencyKit is a lightweight library and a collection of Swift Macros designed to make your transition to Swift 6 safe, fast, and painless. Forget about memory leaks caused by `unstructured tasks` and the tedious manual rewriting of legacy code.

## 🌟 Features

* **`TaskVault`**: A thread-safe Actor for automatic `Task` lifecycle management. Think of it as `DisposeBag` from RxSwift, but built natively for Swift 6.
* **`@AsyncBridge`**: A powerful Swift Macro that automatically generates modern `async throws` functions on top of your legacy methods utilizing `completion handlers`.
* **100% Strict Concurrency Proof**: Zero Data Races and zero compiler warnings under Swift 6 strict concurrency checks.

## 📦 Installation (Swift Package Manager)

Add the package to your `Package.swift` file or integrate it via Xcode (File -> Add Packages...):

```swift
dependencies: [
    .package(url: "[https://github.com/PavelAndreev13/ConcurrencyKit](https://github.com/PavelAndreev13/ConcurrencyKit.git)", from: "1.0.0")
]
