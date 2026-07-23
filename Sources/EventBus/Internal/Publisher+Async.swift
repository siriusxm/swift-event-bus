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

@preconcurrency import Combine

extension Publisher where Failure == Never, Output: Sendable {
    /// Asynchronously transforms each `Output` into a `T`, one at a time, in-order.
    ///
    /// Upstream values are buffered so none are dropped while a transform is in flight.
    func asyncMap<T: Sendable>(
        priority: TaskPriority? = nil,
        isolation: isolated (any Actor)? = #isolation,
        _ transform: @escaping @Sendable (Output) async -> T
    ) -> AnyPublisher<T, Never> {
        buffer(size: .max, prefetch: .byRequest, whenFull: .dropOldest)
            .flatMap(maxPublishers: .max(1)) { value in
                Future { promise in
                    Task(priority: priority) {
                        _ = isolation
                        let output = await transform(value)
                        promise(.success(output))
                    }
                }
            }
            .eraseToAnyPublisher()
    }
}

extension Publisher where Output: Sendable {
    /// Provides an `AsyncSequence` from a `Publisher`, buffering elements received from
    /// the upstream publisher so none are dropped before the consumer reads them.
    var bufferedValues: AsyncThrowingStream<Output, Error> {
        AsyncThrowingStream<Output, Error>(bufferingPolicy: .unbounded) { continuation in
            let cancellable = sink(
                receiveCompletion: {
                    switch $0 {
                    case .finished: continuation.finish()
                    case let .failure(error): continuation.finish(throwing: error)
                    }
                },
                receiveValue: { continuation.yield($0) }
            )

            continuation.onTermination = { @Sendable _ in
                cancellable.cancel()
            }
        }
    }
}
