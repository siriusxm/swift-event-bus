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

/// Links two arbitrary `SimpleBusEventType` events together as a trigger-response pair.
///
/// Use `SimpleBusEventLink` when you want to reuse the same `ResponseEvent` for different `TriggerEvent` types
/// with related but separate handlers. This can also be used in testing to invoke a `TriggerEvent`
/// and wait for a side-effect or intermediate event rather than the normally defined response event.
public protocol SimpleBusEventLink: Sendable {
    associatedtype TriggerEvent: SimpleBusEventType
    associatedtype ResponseEvent: SimpleBusEventType
}

public extension SimpleBusEventLink {
    typealias TrackedResponse = ResponseEvent.TrackedEvent
    typealias TriggerEventPayload = TriggerEvent.Payload

    /// Sends this event from within a `TrackedBusEventHandler` function and waits for the response.
    ///
    /// This variant uses the latest event that is available in a `TrackedBusEventHandler` function to create and send a `TriggerEvent`,
    /// then awaits the corresponding `ResponseEvent.TrackedEvent` event. The `inputEvent` history is automatically chained into the response.
    /// This function will return `nil` if the `EventBus` has been deallocated while the handler function is still asynchronously running.
    /// So `TrackedBusEventHandler` functions should immediately return `nil` on receiving a `nil` from this function with no further processing.
    ///
    /// - Parameters:
    ///   - inputEvent: The `TrackedBusEvent` that is the latest event in the chain of the `TrackedBusEventHandler` function.
    ///   - payload: The `TriggerEvent.Payload` data defined for the `TriggerEvent`.
    ///   - timeout: Optional timeout duration; defaults to the `EventBus` default if not specified.
    /// - Returns: The `ResponseEvent.TrackedEvent` returned from the handler, or `nil` if the `EventBus` has been deallocated.
    static func sendAndWaitForResponse(
        inputEvent: AnyTrackedBusEventType,
        payload: TriggerEvent.Payload,
        timeout: Duration? = nil
    ) async throws -> ResponseEvent.TrackedEvent? {
        try await inputEvent.eventBusCallback?.sendAndWaitForMatchingResult(
            inputEvent,
            TriggerEvent.event(payload: payload),
            resultType: ResponseEvent.eventType,
            matchingOption: .indirectResponse,
            timeout: timeout ?? inputEvent.eventBusCallback?.defaultTimeout ?? .zero
        )
    }

    /// Sends this event from a function that has access to an `EventBus` and waits for the response.
    ///
    /// This variant uses a reference to the `EventBus` to create and send a `TriggerEvent`,
    /// then awaits the corresponding `ResponseEvent.TrackedEvent` event.
    /// The resulting event starts a new event chain in the bus.
    ///
    /// - Parameters:
    ///   - eventBus: A reference to an `EventBus` into which the new event will be sent.
    ///   - payload: The `TriggerEventPayload` data defined for the `TriggerEvent`.
    ///   - timeout: Optional timeout duration; defaults to the `EventBus` default if not specified.
    /// - Returns: The `ResponseEvent.TrackedEvent` returned from the handler
    static func sendAndWaitForResponse(
        eventBus: EventBus,
        payload: TriggerEvent.Payload,
        timeout: Duration? = nil
    ) async throws -> ResponseEvent.TrackedEvent {
        try await eventBus.sendAndWaitForMatchingResult(
            TriggerEvent.event(payload: payload),
            resultType: ResponseEvent.eventType,
            matchingOption: .indirectResponse,
            timeout: timeout ?? eventBus.defaultTimeout
        )
    }
}

// MARK: - Void Payload Conveniences

/// Sends this event from within a `TrackedBusEventHandler` function and waits for the response.
///
/// This is a convenience method for links where the `TriggerEvent` doesn't require input data.
/// See ``sendAndWaitForResponse(inputEvent:payload:timeout:)`` for full documentation.
///
/// - Parameters:
///   - inputEvent: The `TrackedBusEvent` that is the latest event in the chain of the `TrackedBusEventHandler` function.
///   - timeout: Optional timeout duration; defaults to the `EventBus` default if not specified.
/// - Returns: The `ResponseEvent.TrackedEvent` returned from the handler, or `nil` if the `EventBus` has been deallocated.
public extension SimpleBusEventLink where TriggerEvent.Payload == Void {
    static func sendAndWaitForResponse(
        inputEvent: AnyTrackedBusEventType,
        timeout: Duration? = nil
    ) async throws -> ResponseEvent.TrackedEvent? {
        try await sendAndWaitForResponse(inputEvent: inputEvent, payload: (), timeout: timeout)
    }

    /// Sends this event from a function that has access to an `EventBus` and waits for the response.
    ///
    /// This is a convenience method for links where the `TriggerEvent` doesn't require input data.
    /// See ``sendAndWaitForResponse(eventBus:payload:timeout:)`` for full documentation.
    ///
    /// - Parameters:
    ///   - eventBus: A reference to an `EventBus` into which the new event will be sent.
    ///   - timeout: Optional timeout duration; defaults to the `EventBus` default if not specified.
    /// - Returns: The `ResponseEvent.TrackedEvent` returned from the handler.
    static func sendAndWaitForResponse(
        eventBus: EventBus,
        timeout: Duration? = nil
    ) async throws -> ResponseEvent.TrackedEvent {
        try await sendAndWaitForResponse(eventBus: eventBus, payload: (), timeout: timeout)
    }
}

// MARK: - LinkedEventHandler types

/// Declares a handler that takes a `TriggerEvent` and returns a `ResponseEvent` using simple payload functions.
///
/// Use this protocol when you want to define a handler that takes a `TriggerEvent.Payload` and returns a `ResponseEvent.Payload`,
/// reusing event types defined elsewhere rather than declaring new dedicated events.
public protocol LinkedEventPayloadHandler: SimpleBusEventLink {
    typealias HandlerType = @Sendable (TriggerEvent.Payload) async throws -> ResponseEvent.Payload

    static var concurrencyType: EventBus.ConcurrencyType { get }
    static var serviceName: ServiceName { get }
}

public extension LinkedEventPayloadHandler {
    static var concurrencyType: EventBus.ConcurrencyType { .parallel }
    static var serviceName: ServiceName { "Default Name" }

    /// Returns a registration record for a handler function that processes this event link.
    ///
    /// This method wraps a simple handler function or closure that takes a `TriggerEvent.Payload` and returns a `ResponseEvent.Payload`
    /// into an `EventBusHandler` record suitable for registration with an `EventBus`.
    /// The handler is automatically wrapped to convert its response payload into a `ResponseEvent`.
    ///
    /// - Parameter handler: A function or closure that receives a `TriggerEvent.Payload` and asynchronously returns a `ResponseEvent.Payload`.
    /// - Returns: An `EventBusHandler` record that can be passed to the `EventBus` `register` function.
    @Sendable static func handlerRegistration(
        _ handler: @escaping HandlerType
    ) -> EventBusHandler<ObjectIdentifier, TriggerEventPayload> {
        let handlerAdapter: @Sendable (TriggerEventPayload) async throws -> [ResponseEvent.Event] = { payload in
            let responsePayload = try await handler(payload)
            return [ResponseEvent.event(payload: responsePayload)]
        }

        return EventBusHandler(
            concurrencyType,
            handler: handlerAdapter,
            eventType: TriggerEvent.eventType,
            serviceName: serviceName
        )
    }
}

/// Declares a handler that takes a `TriggerEvent` and returns a `ResponseEvent` using tracked event functions.
///
/// Use this protocol when you want to define a handler that receives a `TriggerEvent.TrackedEvent` and returns a `TrackedResponse`,
/// allowing it to send additional events into the bus and chain event histories,
/// while reusing event types defined elsewhere rather than declaring new dedicated events.
public protocol LinkedTrackedBusEventHandler: SimpleBusEventLink {
    typealias HandlerType = @Sendable (TriggerEvent.TrackedEvent) async throws -> TrackedResponse?

    static var concurrencyType: EventBus.ConcurrencyType { get }
    static var serviceName: ServiceName { get }
}

public extension LinkedTrackedBusEventHandler {
    static var concurrencyType: EventBus.ConcurrencyType { .parallel }
    static var serviceName: ServiceName { "Default Name" }

    /// Returns a registration record for a handler function that processes this event link.
    ///
    /// This method wraps a handler function or closure that takes a `TriggerEvent.TrackedEvent` and returns a `TrackedResponse?`
    /// into an `EventBusHandler` record suitable for registration with an `EventBus`.
    /// The handler function receives a tracked event, allowing it to send additional events into the bus and chain event histories.
    ///
    /// - Parameter handler: A function or closure that receives a `TriggerEvent.TrackedEvent` and asynchronously returns a `TrackedResponse?`.
    /// - Returns: An `EventBusHandler` record that can be passed to the `EventBus` `register` function.
    @Sendable static func handlerRegistration(
        _ handler: @escaping HandlerType
    ) -> EventBusHandler<ObjectIdentifier, TriggerEventPayload> {
        let trackedBusEventHandler: @Sendable (TriggerEvent.TrackedEvent) async throws -> [AnyTrackedBusEventType?]? = { inputEvent in
            try await [handler(inputEvent)]
        }

        return EventBusHandler(
            concurrencyType,
            trackedBusEventHandler: trackedBusEventHandler,
            eventType: TriggerEvent.eventType,
            serviceName: serviceName
        )
    }
}
