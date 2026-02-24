import Foundation

private protocol AnyCancellable: Sendable {
    func cancel()
}

private struct TaskCancellable: AnyCancellable {
    let cancelAction: @Sendable () -> Void
    
    func cancel() {
        cancelAction()
    }
}

public actor TaskVault {
    private var tasks: [UUID: AnyCancellable] = [:]
    
    public init() {}
    
    @discardableResult
    public func store<Success, Failure: Error>(_ task: Task<Success, Failure>) -> UUID {
        let id = UUID()
        
        tasks[id] = TaskCancellable(cancelAction: {
            task.cancel()
        })
        
        return id
    }
    
    public func cancel(id: UUID) {
        tasks[id]?.cancel()
        tasks.removeValue(forKey: id)
    }
    
    public func cancelAll() {
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()
    }
    
    deinit {
        for task in tasks.values {
            task.cancel()
        }
    }
}


public extension Task {
    
    @discardableResult
    func store(in vault: isolated TaskVault) -> Self {
        Task<Void, Never> {
            await vault.store(self)
        }
        return self
    }
}
