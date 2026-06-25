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

/// Declares a reusable event that is not tied to a specific handler function.
///
/// Use `SimpleBusEventType` when you want to create an event that your component publishes
/// to inform the rest of the system that something happened, but that your component does not handle directly.
/// This can also be an event that several different but related handlers reuse as a common response.
public protocol SimpleBusEventType<Payload>: Sendable {
    associatedtype Payload: Sendable = Void
    typealias Event = BusEvent<ObjectIdentifier, Payload>
    typealias TrackedEvent = TrackedBusEvent<ObjectIdentifier, Payload>

    /// A debug name for this event type.
    ///
    /// Defaults to `String(reflecting: Self.self)`.
    /// Can be overridden to provide a cleaner name for generic wrapper types.
    static var debugName: String { get }
}

public extension SimpleBusEventType {
    /// A unique identifier for this event type.
    ///
    /// Used internally for event routing, logging, and cancellation.
    static var eventType: ObjectIdentifier {
        ObjectIdentifier(Self.self)
    }

    /// Default implementation returns the fully reflected type name.
    static var debugName: String {
        String(reflecting: Self.self)
    }

    /// Used internally, and for manually creating an event.
    ///
    /// For most cases `send` functions will create events for you.
    ///
    /// - Parameter payload: The `Payload` data defined for this event.
    /// - Returns: An `Event` created from the provided payload.
    static func event(payload: Payload) -> Event {
        Event(eventType: eventType, payload: payload, debugName: debugName)
    }

    /// Sends this event from within a `TrackedBusEventHandler` function without waiting for a response.
    ///
    /// This variant uses an `inputEvent` available in a `TrackedBusEventHandler` function to create and send a side-effect event
    /// that branches off into a separate event chain. The resulting event can't be chained into the current handler function's result event history,
    /// and this `send` function will return immediately before this new event is handled.
    ///
    /// - Parameters:
    ///   - inputEvent: The `TrackedBusEvent` that is the latest event in the chain of the `TrackedBusEventHandler` function.
    ///   - payload: The `Payload` data defined for this event.
    static func send(inputEvent: AnyTrackedBusEventType, payload: Payload) async {
        await inputEvent.eventBusCallback?.send(inputEvent, event(payload: payload))
    }

    /// Sends this event from a function that has access to an `EventBus` without waiting for a response.
    ///
    /// This variant uses a reference to the `EventBus` to create and broadcast an event into the bus without waiting for a response.
    /// This `send` function will return immediately before this new event is handled, and the resulting event will start a new event chain in the bus.
    ///
    /// - Parameters:
    ///   - eventBus: A reference to an `EventBus` into which the new event will be sent.
    ///   - payload: The `Payload` data defined for this event.
    static func send(eventBus: EventBus, payload: Payload) async {
        await eventBus.send(event(payload: payload))
    }
}

// MARK: - Void Payload Conveniences

public extension SimpleBusEventType where Payload == Void {
    /// Used internally, and for manually creating an event with no payload.
    ///
    /// For most cases `send` functions will create events for you.
    ///
    /// - Returns: An `Event` with an empty payload.
    static func event() -> Event {
        event(payload: ())
    }

    /// Sends this event from within a `TrackedBusEventHandler` function without waiting for a response.
    ///
    /// This is a convenience method for events that don't require input data.
    /// See ``send(inputEvent:payload:)`` for full documentation.
    ///
    /// - Parameter inputEvent: The `TrackedBusEvent` that is the latest event in the chain of the `TrackedBusEventHandler` function.
    static func send(inputEvent: AnyTrackedBusEventType) async {
        await send(inputEvent: inputEvent, payload: ())
    }

    /// Sends this event from a function that has access to an `EventBus` without waiting for a response.
    ///
    /// This is a convenience method for events that don't require input data.
    /// See ``send(eventBus:payload:)`` for full documentation.
    ///
    /// - Parameter eventBus: A reference to an `EventBus` into which the new event will be sent.
    static func send(eventBus: EventBus) async {
        await send(eventBus: eventBus, payload: ())
    }
}
