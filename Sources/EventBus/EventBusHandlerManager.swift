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
import ConcurrencyExtras
import Foundation

/// is an internal delegate class that separates out the array of handlers on the EventBus.
/// It implements registration, deregistration, and lookup
final class EventBusHandlerManager: Sendable {
    private let handlers = LockIsolated<[EventBusHandlerID: EventBusHandlerRecord]>([:])

    private func setHandler(for id: EventBusHandlerID, _ record: EventBusHandlerRecord) {
        handlers.withValue { $0[id] = record }
    }

    func handlerIDs(for serviceName: ServiceName) -> [EventBusHandlerID] {
        handlers.withValue {
            $0.values
                .filter { $0.serviceName == serviceName }
                .map(\.handlerID)
        }
    }

    // MARK: - utility functions for adding & removing/cancelling handlers

    func addHandler(
        cancellable: AnyCancellable,
        eventType: AnyEventType,
        serviceName: ServiceName,
    ) -> EventBusHandlerID {
        let handlerID = UUID()
        setHandler(for: handlerID, EventBusHandlerRecord(
            cancellable: cancellable,
            eventType: eventType,
            handlerID: handlerID,
            serviceName: serviceName,
        ))
        return handlerID
    }

    func cancelHandler(_ handlerID: EventBusHandlerID) {
        handlers.withValue {
            if let handlerRecord = $0[handlerID] {
                $0[handlerID] = nil
                handlerRecord.cancellable.cancel()
            }
        }
    }

    func cancelHandlers(for serviceName: ServiceName) {
        handlers.withValue {
            for (id, handler) in $0 where handler.serviceName == serviceName {
                handler.cancellable.cancel()
                $0[id] = nil
            }
        }
    }

    func removeHandlers<EventType: Equatable & Sendable>(for eventType: EventType, serviceName: ServiceName) {
        handlers.withValue {
            for (id, handler) in $0 where handler.serviceName == serviceName &&
                eventType == (handler.eventType as? EventType)
            {
                handler.cancellable.cancel()
                $0[id] = nil
            }
        }
    }
}

// swiftformat:disable opaqueGenericParameters

// MARK: - Parallel Handlers

extension EventBusHandlerManager {
    func addParallelTrackedBusEventHandler<EventType: Equatable & Sendable, Payload: Sendable>(
        _ handler: @escaping EventBus.TrackedBusEventHandler<EventType, Payload>,
        eventBus: EventBus,
        eventType: EventType,
        priority: TaskPriority? = nil,
        serviceName: ServiceName
    ) -> EventBusHandlerID {
        addHandler(
            cancellable: eventBus.attachParallelTrackedBusEventHandler(
                eventType,
                priority: priority,
                handler: handler
            ),
            eventType: eventType,
            serviceName: serviceName
        )
    }

    func addParallelEventHandler<EventType: Equatable & Sendable, Payload: Sendable>(
        _ handler: @escaping EventBus.Handler<Payload>,
        eventBus: EventBus,
        eventType: EventType,
        priority: TaskPriority? = nil,
        serviceName: ServiceName
    ) -> EventBusHandlerID {
        addHandler(
            cancellable: eventBus.attachParallelHandler(
                eventType,
                priority: priority,
                handler: handler
            ),
            eventType: eventType,
            serviceName: serviceName
        )
    }
}

// MARK: - Serial Handlers

extension EventBusHandlerManager {
    func addSerialEventHandler<EventType: Equatable & Sendable, Payload: Sendable>(
        _ handler: @escaping EventBus.Handler<Payload>,
        eventBus: EventBus,
        eventType: EventType,
        priority: TaskPriority? = nil,
        serviceName: ServiceName
    ) -> EventBusHandlerID {
        addHandler(
            cancellable: eventBus.attachSerialHandler(
                eventType,
                priority: priority,
                handler: handler
            ),
            eventType: eventType,
            serviceName: serviceName
        )
    }

    func addSerialTrackedBusEventHandler<EventType: Equatable & Sendable, Payload: Sendable>(
        _ handler: @escaping EventBus.TrackedBusEventHandler<EventType, Payload>,
        eventBus: EventBus,
        eventType: EventType,
        priority: TaskPriority? = nil,
        serviceName: ServiceName
    ) -> EventBusHandlerID {
        addHandler(
            cancellable: eventBus.attachSerialTrackedBusEventHandler(
                eventType,
                priority: priority,
                handler: handler
            ),
            eventType: eventType,
            serviceName: serviceName
        )
    }
}

// MARK: - Restart Handlers

extension EventBusHandlerManager {
    func addRestartEventHandler<EventType: Equatable & Sendable, Payload: Sendable>(
        _ handler: @escaping EventBus.Handler<Payload>,
        eventBus: EventBus,
        eventType: EventType,
        priority: TaskPriority? = nil,
        serviceName: ServiceName
    ) -> EventBusHandlerID {
        addHandler(
            cancellable: eventBus.attachRestartHandler(
                eventType,
                priority: priority,
                handler: handler
            ),
            eventType: eventType,
            serviceName: serviceName
        )
    }

    func addRestartTrackedBusEventHandler<EventType: Equatable & Sendable, Payload: Sendable>(
        _ handler: @escaping EventBus.TrackedBusEventHandler<EventType, Payload>,
        eventBus: EventBus,
        eventType: EventType,
        priority: TaskPriority? = nil,
        serviceName: ServiceName
    ) -> EventBusHandlerID {
        addHandler(
            cancellable: eventBus.attachRestartTrackedBusEventHandler(
                eventType,
                priority: priority,
                handler: handler
            ),
            eventType: eventType,
            serviceName: serviceName
        )
    }
}
