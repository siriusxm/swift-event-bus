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

// swiftformat:disable opaqueGenericParameters
public extension EventBus {
    // MARK: - add functions that register handlers

    /// Add function for a TrackedBusEvent handler which accepts a reference to the more complex TrackedBusEvent with it's internal event history and weak EventBusCallback reference
    /// - Parameters:
    ///   - concurrencyType: the execution mode for this handler.
    ///   - trackedBusEventHandler: the handler function. This function takes the TrackedBusEvent that triggered the handler
    ///              and returns any number of BusResults, which will be sent to the bus in order, but execution order is not guaranteed
    ///   - eventType: an event type that the bus will filter for when passing events to this handler
    ///   - priority: the priority for the task containing a single invocation of the handler to handle an event
    ///   - serviceName - an identifier for the service this handler is associated with, can be used to specify registered handlers as a group
    /// - Returns: The ID of the registered handler, can be used for identifying a specific handler on the bus
    @discardableResult internal func add<EventType: Equatable & Sendable, Payload: Sendable>(
        _ concurrencyType: ConcurrencyType,
        trackedBusEventHandler: @escaping TrackedBusEventHandler<EventType, Payload>,
        eventType: EventType,
        priority: TaskPriority? = nil,
        serviceName: ServiceName
    ) -> EventBusHandlerID {
        switch concurrencyType {
        case .parallel:
            handlerManager.addParallelTrackedBusEventHandler(
                trackedBusEventHandler,
                eventBus: self,
                eventType: eventType,
                priority: priority,
                serviceName: serviceName
            )

        case .serial:
            handlerManager.addSerialTrackedBusEventHandler(
                trackedBusEventHandler,
                eventBus: self,
                eventType: eventType,
                priority: priority,
                serviceName: serviceName
            )

        case .restart:
            handlerManager.addRestartTrackedBusEventHandler(
                trackedBusEventHandler,
                eventBus: self,
                eventType: eventType,
                priority: priority,
                serviceName: serviceName
            )
        }
    }

    /// Adds a handler function to the bus that is executed for any matching events on the bus as they occur, whether processing for each event is overlapping or not.
    /// This simple integration allows for handlers to process events independent of event ordering, and to return any number of events to the bus as a result of that processing.
    /// - Parameters:
    ///   - concurrencyType: the execution mode for this handler.
    ///   - handler: the handler function. This function takes a single argument object and returns any number of events, which will be executed on the bus in an unspecified
    ///   - eventType: an event type that the bus will filter for when passing events to this handler
    ///   - priority: the priority for each task containing a single invocation of the handler to handle an event
    ///   - serviceName - an identifier for the service this handler is associated with, can be used to specify registered handlers as a group
    /// - Returns: The ID of the registered handler, can be used for identifying a specific handler on the bus
    @discardableResult internal func add<EventType: Equatable & Sendable, Payload: Sendable>(
        _ concurrencyType: ConcurrencyType,
        handler: @escaping Handler<Payload>,
        eventType: EventType,
        priority: TaskPriority? = nil,
        serviceName: ServiceName
    ) -> EventBusHandlerID {
        switch concurrencyType {
        case .parallel:
            handlerManager.addParallelEventHandler(
                handler,
                eventBus: self,
                eventType: eventType,
                priority: priority,
                serviceName: serviceName
            )

        case .serial:
            handlerManager.addSerialEventHandler(
                handler,
                eventBus: self,
                eventType: eventType,
                priority: priority,
                serviceName: serviceName
            )

        case .restart:
            handlerManager.addRestartEventHandler(
                handler,
                eventBus: self,
                eventType: eventType,
                priority: priority,
                serviceName: serviceName
            )
        }
    }

    // MARK: - utility functions for listing and removing/cancelling handlers

    func handlerIDs(for serviceName: ServiceName) -> [EventBusHandlerID] {
        handlerManager.handlerIDs(for: serviceName)
    }

    func remove(handler: EventBusHandlerID) {
        handlerManager.cancelHandler(handler)
    }

    func remove(service: ServiceName) {
        handlerManager.cancelHandlers(for: service)
    }

    func remove<EventType: Equatable & Sendable>(for eventType: EventType, serviceName: ServiceName) {
        handlerManager.removeHandlers(for: eventType, serviceName: serviceName)
    }

    func register(handlers: [any Handlable]) {
        for handler in handlers {
            handler.handlerRegistration(self)
        }
    }
}

// swiftformat:enable opaqueGenericParameters
