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

/// Base protocol for generic TrackedBusEvent primitives that carry event history.
///
/// A tracked event wraps a `BusEventType` along with its processing history and a callback reference to the `EventBus`,
/// enabling event chaining and history accumulation across handler calls.
/// `TrackedBusEventType` is the main type used internally in the `EventBus`
public protocol TrackedBusEventType<EventType, Payload>: Sendable {
    associatedtype EventType: Equatable & Sendable
    associatedtype Payload: Sendable

    var eventBusCallback: EventBusCallback? { get }
    var eventHistory: BusEventProcessRecord { get }
    var busEvent: any BusEventType<EventType, Payload> { get }
}

/// Used to type-erase TrackedBusEvent primitives.
public typealias AnyTrackedBusEventType = any TrackedBusEventType

/// A type-erased container for tracked bus events.
///
/// Used internally to store or pass tracked events without preserving their specific type information.
struct ErasedTrackedBusEvent: Sendable {
    public let eventHistory: BusEventProcessRecord
    public let busEvent: any BusEventType

    public init(eventHistory: BusEventProcessRecord, busEvent: any BusEventType) {
        self.eventHistory = eventHistory
        self.busEvent = busEvent
    }
}

/// Primitive base generic for tracked bus events with typed payload access.
///
/// For user-visible tracked events, this struct allows specifying the `EventType` and `Payload` types.
/// The current (last) event in event history is copied out and typed for non-optional access as `busEvent`.
/// Best used internally to create new event interaction paradigms. See ``SimpleBusEventType``.
public struct TrackedBusEvent<EventType: Equatable & Sendable, Payload: Sendable>: TrackedBusEventType {
    public let eventHistory: BusEventProcessRecord
    public let busEvent: any BusEventType<EventType, Payload>
    private weak var eventBus: EventBus?

    public var eventBusCallback: EventBusCallback? {
        eventBus
    }

    public init(busEvent: any BusEventType<EventType, Payload>, eventBus: EventBus) {
        eventHistory = eventBus.history(with: busEvent)
        self.busEvent = busEvent
        self.eventBus = eventBus
    }

    public init(eventHistory: BusEventProcessRecord, busEvent: any BusEventType<EventType, Payload>, eventBus: EventBusCallback?) {
        self.eventHistory = eventHistory
        self.busEvent = busEvent
        self.eventBus = eventBus as? EventBus
    }
}

// swiftformat:disable opaqueGenericParameters
public extension TrackedBusEventType {
    /// Appends an event to the current event history and returns a new tracked event.
    ///
    /// Use this when you need to chain events within a handler function while preserving the event history.
    ///
    /// - Parameter event: A `BusEvent` to append to the history.
    /// - Returns: A new `TrackedBusEvent` containing the appended event with accumulated history, or `nil` if the `EventBus` has been deallocated.
    func appendEvent<NewEventType: Equatable & Sendable, NewPayload: Sendable>(
        _ event: BusEvent<NewEventType, NewPayload>
    ) async -> TrackedBusEvent<NewEventType, NewPayload>? {
        await eventBusCallback?.trackedBusEvent(self, event)
    }
}

// swiftformat:enable opaqueGenericParameters
