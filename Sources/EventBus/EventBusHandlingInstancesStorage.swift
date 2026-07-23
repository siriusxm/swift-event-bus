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
        let task: Task<Void, Never>
    }

    private let handlerTasks = LockIsolated<[UUID: HandlerTask]>([:])

    func addHandling(task: Task<Void, Never>, for event: any EventType) -> UUID {
        let uuid = UUID()
        handlerTasks.withValue { $0[uuid] = HandlerTask(inputEventType: event, task: task) }
        return uuid
    }

    func removeHandlingTask(with uuid: UUID) {
        handlerTasks.withValue { $0[uuid] = nil }
    }

    func cancelHandlingTasks<T: EventType>(for event: T) {
        handlerTasks.withValue { dict in
            let matchingUUIDs = dict.compactMap { uuid, handlerTask in
                if let storedEvent = handlerTask.inputEventType as? T, storedEvent == event {
                    return uuid
                }
                return nil
            }

            for uuid in matchingUUIDs {
                dict[uuid]?.task.cancel()
                dict.removeValue(forKey: uuid)
            }
        }
    }

    func replaceAllHandlingTasks(with task: Task<Void, Never>, matching event: any EventType) -> UUID {
        cancelHandlingTasks(for: event)
        return addHandling(task: task, for: event)
    }
}
