// The Swift Programming Language
// https://docs.swift.org/swift-book

@freestanding(expression)

public macro AsyncBridge() -> () = #externalMacro(module: "ConcurrencyKitMacros", type: "AsyncBridgeMacro")
