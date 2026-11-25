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

import ConcurrencyExtras

/// A task whose operation is held until an external caller either starts or discards it.
///
/// Cancellation does not resolve the start decision. If the task is started after being
/// cancelled, its operation runs with `Task.isCancelled == true`.
final class DeferredStartTask: Sendable {
    private final class StartControl: Sendable {
        private enum State: Sendable {
            case unresolved
            case waiting(CheckedContinuation<Bool, Never>)
            case resolved(Bool)
        }

        private let state = LockIsolated(State.unresolved)

        func waitForStartDecision() async -> Bool {
            await withCheckedContinuation { continuation in
                let resolvedDecision = state.withValue { state -> Bool? in
                    switch state {
                    case .unresolved:
                        state = .waiting(continuation)
                        return nil
                    case let .resolved(shouldStart):
                        return shouldStart
                    case .waiting:
                        preconditionFailure("DeferredStartTask can only wait for its start decision once")
                    }
                }
                if let resolvedDecision {
                    continuation.resume(returning: resolvedDecision)
                }
            }
        }

        func resolve(shouldStart: Bool) {
            let continuation = state.withValue { state -> CheckedContinuation<Bool, Never>? in
                switch state {
                case .unresolved:
                    state = .resolved(shouldStart)
                    return nil
                case let .waiting(continuation):
                    state = .resolved(shouldStart)
                    return continuation
                case .resolved:
                    return nil
                }
            }
            continuation?.resume(returning: shouldStart)
        }
    }

    private let startControl: StartControl
    let task: Task<Void, Never>

    init(
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async -> Void
    ) {
        let startControl = StartControl()
        self.startControl = startControl
        task = Task(priority: priority) {
            guard await startControl.waitForStartDecision() else {
                return
            }
            await operation()
        }
    }

    deinit {
        startControl.resolve(shouldStart: false)
    }

    func start() {
        startControl.resolve(shouldStart: true)
    }

    func discard() {
        startControl.resolve(shouldStart: false)
    }

    func waitForCompletion() async {
        await task.value
    }
}
