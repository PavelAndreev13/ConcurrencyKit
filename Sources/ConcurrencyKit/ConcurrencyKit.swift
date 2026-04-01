// The Swift Programming Language
// https://docs.swift.org/swift-book

@attached(peer, names: overloaded)
public macro AsyncBridge() = #externalMacro(module: "ConcurrencyKitMacros", type: "AsyncBridgeMacro")
