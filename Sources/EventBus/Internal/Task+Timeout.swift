//
//  Copyright 2026 Sirius XM Radio LLC
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

extension Task where Failure == Error {
    /// Starts a new `Task` with a timeout. If the timeout expires before the operation
    /// completes, the task is cancelled and an error is thrown.
    init(
        priority: TaskPriority? = nil,
        maximumDuration: Duration,
        operation: @escaping @Sendable () async throws -> Success
    ) {
        self = Task(priority: priority) {
            let stream = AsyncStream<Result<Success, Failure>>.makeStream()

            let work = _Concurrency.Task {
                await withTaskCancellationHandler(operation: {
                    do {
                        let result = try await operation()
                        stream.continuation.yield(.success(result))
                    } catch {
                        stream.continuation.yield(.failure(error))
                    }
                }, onCancel: {
                    stream.continuation.finish()
                })
            }

            let timeout = _Concurrency.Task {
                do {
                    try await _Concurrency.Task.sleep(for: maximumDuration)
                    throw TaskTimeoutError()
                } catch {
                    stream.continuation.yield(.failure(error))
                }
            }

            if let firstResult = await stream.stream.first(where: { _ in true }) {
                return try firstResult.get()
            } else {
                work.cancel()
                timeout.cancel()
                throw _Concurrency.CancellationError()
            }
        }
    }
}

struct TaskTimeoutError: LocalizedError {
    let errorDescription: String? = "Task timed out before completion"
}
