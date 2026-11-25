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
import Foundation

final class EventBusHandlingInstancesStorage: Sendable {
    typealias EventType = Equatable & Sendable

    private struct HandlerTask: Sendable {
        let inputEventType: any EventType
        let serialInputEventSequenceIndex: EventSequenceIndex?
        let task: Task<Void, Never>
    }

    private struct SerialCancellationCutoff: Sendable {
        let inputEventType: any EventType
        var eventSequenceIndex: EventSequenceIndex
    }

    private struct State: Sendable {
        var handlerTasks: [UUID: HandlerTask] = [:]
        var serialCancellationCutoffs: [SerialCancellationCutoff] = []
    }

    private let state = LockIsolated(State())

    func addHandling(task: Task<Void, Never>, for event: any EventType) -> UUID {
        let uuid = UUID()
        state.withValue { state in
            state.handlerTasks[uuid] = HandlerTask(
                inputEventType: event,
                serialInputEventSequenceIndex: nil,
                task: task
            )
        }
        return uuid
    }

    func addSerialHandling<T: EventType>(
        task: Task<Void, Never>,
        for event: T,
        at eventSequenceIndex: EventSequenceIndex
    ) -> UUID? {
        let uuid = UUID()
        return state.withValue { state in
            if serialCancellationCutoff(for: event, in: state).map({ eventSequenceIndex <= $0 }) ?? false {
                return nil
            }

            state.handlerTasks[uuid] = HandlerTask(
                inputEventType: event,
                serialInputEventSequenceIndex: eventSequenceIndex,
                task: task
            )
            return uuid
        }
    }

    func removeHandlingTask(with uuid: UUID) {
        state.withValue { $0.handlerTasks[uuid] = nil }
    }

    func cancelHandlingTasks<T: EventType>(
        for event: T,
        through cancellationCutoff: EventSequenceIndex
    ) {
        state.withValue { state in
            recordSerialCancellationCutoff(cancellationCutoff, for: event, in: &state)
            let matchingUUIDs = state.handlerTasks.compactMap { uuid, handlerTask in
                if eventsMatch(handlerTask.inputEventType, event),
                   handlerTask.serialInputEventSequenceIndex.map({ $0 <= cancellationCutoff }) ?? true
                {
                    return uuid
                }
                return nil
            }

            for uuid in matchingUUIDs {
                state.handlerTasks[uuid]?.task.cancel()
                state.handlerTasks.removeValue(forKey: uuid)
            }
        }
    }

    func replaceAllHandlingTasks(with task: Task<Void, Never>, matching event: any EventType) -> UUID {
        cancelActiveHandlingTasks(for: event)
        return addHandling(task: task, for: event)
    }

    private func cancelActiveHandlingTasks<T: EventType>(for event: T) {
        state.withValue { state in
            let matchingUUIDs = state.handlerTasks.compactMap { uuid, handlerTask in
                eventsMatch(handlerTask.inputEventType, event) ? uuid : nil
            }

            for uuid in matchingUUIDs {
                state.handlerTasks[uuid]?.task.cancel()
                state.handlerTasks.removeValue(forKey: uuid)
            }
        }
    }

    private func recordSerialCancellationCutoff<T: EventType>(
        _ eventSequenceIndex: EventSequenceIndex,
        for event: T,
        in state: inout State
    ) {
        if let index = state.serialCancellationCutoffs.firstIndex(where: {
            eventsMatch($0.inputEventType, event)
        }) {
            state.serialCancellationCutoffs[index].eventSequenceIndex = max(
                state.serialCancellationCutoffs[index].eventSequenceIndex,
                eventSequenceIndex
            )
        } else {
            state.serialCancellationCutoffs.append(SerialCancellationCutoff(
                inputEventType: event,
                eventSequenceIndex: eventSequenceIndex
            ))
        }
    }

    private func serialCancellationCutoff<T: EventType>(
        for event: T,
        in state: State
    ) -> EventSequenceIndex? {
        state.serialCancellationCutoffs.first {
            eventsMatch($0.inputEventType, event)
        }?.eventSequenceIndex
    }

    private func eventsMatch<T: EventType>(_ storedEvent: any EventType, _ event: T) -> Bool {
        guard let typedStoredEvent = storedEvent as? T else {
            return false
        }
        return typedStoredEvent == event
    }
}
