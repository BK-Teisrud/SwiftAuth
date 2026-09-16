import Foundation

/// Resumes each waiter once, even if an injected adapter ignores cancellation.
final class AsyncResultGate<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Value, Error>?
  private var result: Result<Value, Error>?
  func install(_ continuation: CheckedContinuation<Value, Error>) {
    let completed = lock.withLock { () -> Result<Value, Error>? in
      if let result { return result }
      self.continuation = continuation
      return nil
    }
    if let completed { continuation.resume(with: completed) }
  }
  func finish(_ result: Result<Value, Error>) {
    let pending = lock.withLock { () -> CheckedContinuation<Value, Error>? in
      guard self.result == nil else { return nil }
      self.result = result
      let pending = continuation
      continuation = nil
      return pending
    }
    pending?.resume(with: result)
  }
}

func awaitShared<Value: Sendable>(_ task: Task<Value, Error>) async throws -> Value {
  let gate = AsyncResultGate<Value>()
  return try await withTaskCancellationHandler {
    try Task.checkCancellation()
    return try await withCheckedThrowingContinuation { continuation in
      gate.install(continuation)
      Task { gate.finish(await task.result) }
    }
  } onCancel: {
    gate.finish(.failure(CancellationError()))
  }
}
