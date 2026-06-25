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

public protocol Handlable: Sendable {
    associatedtype EventType: Equatable & Sendable
    associatedtype Payload: Sendable
    var concurrencyType: EventBus.ConcurrencyType { get }
    var handlerRegistration: @Sendable (EventBus) -> Void { get }
    var eventType: EventType { get }
    var priority: TaskPriority? { get }
    var serviceName: ServiceName { get }
}

/// EventBusHandler models handlers and is used to send handlers in bulk/inline
/// `event.register(:)`
public struct EventBusHandler<EventType: Equatable & Sendable, Payload: Sendable>: Handlable {
    public let concurrencyType: EventBus.ConcurrencyType
    // Needed to support multiple types of event bus handler
    // ex. EventBus.Handler/EventBus.TrackedBusEventHandler
    public let handlerRegistration: @Sendable (EventBus) -> Void
    public let eventType: EventType
    public let priority: TaskPriority?
    public let serviceName: ServiceName

    public init(
        _ concurrencyType: EventBus.ConcurrencyType,
        handler: @escaping EventBus.Handler<Payload>,
        eventType: EventType,
        priority: TaskPriority? = nil,
        serviceName: ServiceName
    ) {
        self.concurrencyType = concurrencyType
        handlerRegistration = { (eventBus: EventBus) in
            eventBus.add(
                concurrencyType,
                handler: handler,
                eventType: eventType,
                priority: priority,
                serviceName: serviceName
            )
        }
        self.eventType = eventType
        self.priority = priority
        self.serviceName = serviceName
    }

    public init(
        _ concurrencyType: EventBus.ConcurrencyType,
        trackedBusEventHandler: @escaping EventBus.TrackedBusEventHandler<EventType, Payload>,
        eventType: EventType,
        priority: TaskPriority? = nil,
        serviceName: ServiceName
    ) {
        self.concurrencyType = concurrencyType
        handlerRegistration = { (eventBus: EventBus) in
            eventBus.add(
                concurrencyType,
                trackedBusEventHandler: trackedBusEventHandler,
                eventType: eventType,
                priority: priority,
                serviceName: serviceName
            )
        }
        self.eventType = eventType
        self.priority = priority
        self.serviceName = serviceName
    }
}
