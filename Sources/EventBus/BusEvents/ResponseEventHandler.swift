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

/// Base protocol for declaring unique dedicated response events for a handler function that responds to a `TriggerEvent` defined elsewhere.
/// Use derived ``ResponsePayloadHandler`` or ``ResponseTrackedBusEventHandler`` to actually declare events.
/// The `TriggerEvent` can be a plain ``SimpleBusEventType``
/// or an event declared in another ``ResponseEventHandler`` or ``RequestResponseEventHandler``.
/// Note each ``ResponseEventHandler`` defines a new dedicated `Response` event that is specific to its type.
/// To reuse the same `Response` event type for different `TriggerEvents` and handlers, see ``SimpleBusEventLink``
public protocol ResponseEventHandler: SimpleBusEventType where Payload == ResponsePayload {
    associatedtype TriggerEvent: SimpleBusEventType
    associatedtype ResponsePayload: Sendable = Void
    associatedtype Payload: Sendable = Void
    typealias TriggerEventPayload = TriggerEvent.Payload

    typealias Response = Event
    typealias TrackedResponse = TrackedEvent

    static var concurrencyType: EventBus.ConcurrencyType { get }
    static var serviceName: ServiceName { get }
}

public extension ResponseEventHandler {
    static var concurrencyType: EventBus.ConcurrencyType { .parallel }
    static var serviceName: ServiceName { "Default Name" }

    /// Used internally, for logging, and for cancelling requests.
    static var eventID: ObjectIdentifier {
        TriggerEvent.eventType
    }

    /// Used internally, for logging, and for cancelling requests.
    static var responseID: ObjectIdentifier {
        eventType
    }

    /// Used internally, and for manually creating a `TriggerEvent`.
    /// Is an alias for the original `TriggerEvent` utility `event` function.
    ///
    /// For most cases `send` and `sendAndWaitForResponse` functions will create trigger events for you.
    ///
    /// - Parameter payload: The `TriggerEventPayload` data defined for the `TriggerEvent`.
    /// - Returns: A `TriggerEvent` created from the provided payload.
    static func event(payload: TriggerEventPayload) -> TriggerEvent.Event {
        TriggerEvent.event(payload: payload)
    }

    /// Creates a response event for use by `TrackedBusEventHandler` functions.
    ///
    /// This helper wraps the given `ResponsePayload` into a `Response` that the `EventBus` will publish after the handler function returns.
    ///
    /// - Parameter payload: The the data returned by the handler function to pass into the `Response` event.
    /// - Returns: A `Response` event created from the provided payload.
    static func response(payload: ResponsePayload) -> Response {
        Response(eventType: responseID, payload: payload, debugName: debugName)
    }
}

public protocol ResponsePayloadHandler: ResponseEventHandler {
    typealias HandlerType = @Sendable (TriggerEventPayload) async throws -> ResponsePayload
}

/// Declares a unique dedicated response event and reuses an externally defined `TriggerEvent`
/// for a handler function that takes and returns simple payloads, or void handler functions.
/// Payload types are defaulted to Void if not specified in the type declaration.
public extension ResponsePayloadHandler {
    /// Returns a registration record for a handler function that processes this event type.
    ///
    /// This method wraps a simple handler function or closure that takes a `TriggerEventPayload` and returns a `ResponsePayload`
    /// into an `EventBusHandler` record suitable for registration with an `EventBus`.
    /// The handler is automatically wrapped to convert its `ResponsePayload` into a `Response` event.
    ///
    /// - Parameter handler: A function or closure that receives a `TriggerEventPayload` and asynchronously returns a `ResponsePayload`.
    /// - Returns: An `EventBusHandler` record that can be passed to the `EventBus` `register` function.
    @Sendable static func handlerRegistration(
        _ handler: @escaping HandlerType
    ) -> EventBusHandler<ObjectIdentifier, TriggerEventPayload> {
        let handlerAdapter: @Sendable (TriggerEventPayload) async throws -> [Self.Response] = { payload in
            let responsePayload = try await handler(payload)
            return [response(payload: responsePayload)]
        }

        return EventBusHandler(
            concurrencyType,
            handler: handlerAdapter,
            eventType: eventID,
            serviceName: serviceName
        )
    }

    /// Sends this event from within a `TrackedBusEventHandler` function and waits for the `TrackedResponse`.
    ///
    /// This variant uses the latest event that is available in a `TrackedBusEventHandler` function to create and send a `TriggerEvent`,
    /// then awaits the corresponding `TrackedResponse` event. The `inputEvent` history is automatically chained into the response.
    /// This function will  return `nil` if the `EventBus` has been deallocated while the handler function is still asynchronously running.
    /// So `TrackedBusEventHandler` functions should immediately return `nil` on receiving a `nil` from this function with no further processing.
    /// Use `send` if you do not need to wait for or track the response.
    ///
    /// - Parameters:
    ///   - inputEvent: The `TrackedBusEvent` that is the latest event in the chain of the `TrackedBusEventHandler` function.
    ///   - payload: The `TriggerEventPayload` data defined for the `TriggerEvent`.
    ///   - timeout: Optional timeout duration; defaults to the `EventBus` default if not specified.
    /// - Returns: The `TrackedResponse` containing the `ResponsePayload`, or `nil` if the `EventBus` has been deallocated.
    static func sendAndWaitForResponse(
        inputEvent: AnyTrackedBusEventType,
        payload: TriggerEventPayload,
        timeout: Duration? = nil
    ) async throws -> TrackedResponse? {
        try await inputEvent.eventBusCallback?.sendAndWaitForMatchingResult(
            inputEvent,
            event(payload: payload),
            resultType: responseID,
            matchingOption: .directResponse,
            timeout: timeout ?? inputEvent.eventBusCallback?.defaultTimeout ?? .zero
        )
    }

    /// Sends this event from a function that has access to an `EventBus` and waits for the response.
    ///
    /// This variant uses a reference to the `EventBus` to create and send a `TriggerEvent`, then awaits the corresponding `TrackedResponse`.
    /// The resulting event starts a new event chain in the bus. Use `send` if you do not need to wait for a response.
    ///
    /// - Parameters:
    ///   - eventBus: A reference to an `EventBus` into which the new event will be sent.
    ///   - payload: The `TriggerEventPayload` data defined for the `TriggerEvent`.
    ///   - timeout: Optional timeout duration; defaults to the `EventBus` default if not specified.
    /// - Returns: The `TrackedResponse` containing the `ResponsePayload`.
    static func sendAndWaitForResponse(
        eventBus: EventBus,
        payload: TriggerEventPayload,
        timeout: Duration? = nil
    ) async throws -> TrackedResponse {
        try await eventBus.sendAndWaitForMatchingResult(
            event(payload: payload),
            resultType: responseID,
            matchingOption: .directResponse,
            timeout: timeout ?? eventBus.defaultTimeout
        )
    }
}

/// Declares a unique dedicated response event and reuses an externally defined `TriggerEvent`
/// for a handler function that posts additional events back into the EventBus.
/// Payload types are defaulted to Void if not specified in the type declaration.
public protocol ResponseTrackedBusEventHandler: ResponseEventHandler {
    typealias HandlerType = @Sendable (TriggerEvent.TrackedEvent) async throws -> TrackedResponse?
}

public extension ResponseTrackedBusEventHandler {
    /// Returns a registration record for a handler function that processes this event type.
    ///
    /// This method wraps a handler function or closure that takes a `TriggerEvent.TrackedEvent` and returns a `TrackedResponse?`
    /// into an `EventBusHandler` record suitable for registration with an `EventBus`.
    /// The handler function receives a `TriggerEvent.TrackedEvent`, allowing it to send additional events into the bus and chain event histories.
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
            eventType: eventID,
            serviceName: serviceName
        )
    }

    /// Sends this event from within a `TrackedBusEventHandler` function and waits for the response.
    ///
    /// This variant uses the latest event that is available in a `TrackedBusEventHandler` function to create and send a `TriggerEvent`,
    /// then awaits the corresponding `TrackedResponse` event. The `inputEvent` history is automatically chained into the response.
    /// This function will return `nil` if the `EventBus` has been deallocated while the handler function is still asynchronously running.
    /// So `TrackedBusEventHandler` functions should immediately return `nil` on receiving a `nil` from this function with no further processing.
    /// Use `send` if you do not need to wait for or track the response.
    ///
    /// - Parameters:
    ///   - inputEvent: The `TrackedBusEvent` that is the latest event in the chain of the `TrackedBusEventHandler` function.
    ///   - payload: The `TriggerEventPayload` data defined for the `TriggerEvent`.
    ///   - timeout: Optional timeout duration; defaults to the `EventBus` default if not specified.
    /// - Returns: The `TrackedResponse` containing the `ResponsePayload`, or `nil` if the `EventBus` has been deallocated.
    static func sendAndWaitForResponse(
        inputEvent: AnyTrackedBusEventType,
        payload: TriggerEventPayload,
        timeout: Duration? = nil
    ) async throws -> TrackedResponse? {
        try await inputEvent.eventBusCallback?.sendAndWaitForMatchingResult(
            inputEvent,
            event(payload: payload),
            resultType: responseID,
            matchingOption: .indirectResponse,
            timeout: timeout ?? inputEvent.eventBusCallback?.defaultTimeout ?? .zero
        )
    }

    /// Sends this event from a function that has access to an `EventBus` and waits for the response.
    ///
    /// This variant uses a reference to the `EventBus` to create and send a `TriggerEvent`, then awaits the corresponding `TrackedResponse`.
    /// The resulting event starts a new event chain in the bus.
    /// Use `send` if you do not need to wait for a response.
    ///
    /// - Parameters:
    ///   - eventBus: A reference to an `EventBus` into which the new event will be sent.
    ///   - payload: The `TriggerEventPayload` data defined for the `TriggerEvent`.
    ///   - timeout: Optional timeout duration; defaults to the `EventBus` default if not specified.
    /// - Returns: The `TrackedResponse` containing the `ResponsePayload`.
    static func sendAndWaitForResponse(
        eventBus: EventBus,
        payload: TriggerEventPayload,
        timeout: Duration? = nil
    ) async throws -> TrackedResponse {
        try await eventBus.sendAndWaitForMatchingResult(
            event(payload: payload),
            resultType: responseID,
            matchingOption: .indirectResponse,
            timeout: timeout ?? eventBus.defaultTimeout
        )
    }
}

// MARK: - Void Payload Conveniences

public extension ResponsePayloadHandler where TriggerEventPayload == Void {
    /// Sends this event from within a `TrackedBusEventHandler` function and waits for the response.
    ///
    /// This is a convenience method for handlers that don't require input data.
    /// See ``sendAndWaitForResponse(inputEvent:payload:timeout:)`` for full documentation.
    ///
    /// - Parameters:
    ///   - inputEvent: The `TrackedBusEvent` that is the latest event in the chain of the `TrackedBusEventHandler` function.
    ///   - timeout: Optional timeout duration; defaults to the `EventBus` default if not specified.
    /// - Returns: The `TrackedResponse` containing the `ResponsePayload`, or `nil` if the `EventBus` has been deallocated.
    static func sendAndWaitForResponse(inputEvent: AnyTrackedBusEventType, timeout: Duration? = nil) async throws -> TrackedResponse? {
        try await sendAndWaitForResponse(inputEvent: inputEvent, payload: (), timeout: timeout)
    }

    /// Sends this event from a function that has access to an `EventBus` and waits for the response.
    ///
    /// This is a convenience method for handlers that don't require input data.
    /// See ``sendAndWaitForResponse(eventBus:payload:timeout:)`` for full documentation.
    ///
    /// - Parameters:
    ///   - eventBus: A reference to an `EventBus` into which the new event will be sent.
    ///   - timeout: Optional timeout duration; defaults to the `EventBus` default if not specified.
    /// - Returns: The `TrackedResponse` containing the `ResponsePayload`.
    static func sendAndWaitForResponse(eventBus: EventBus, timeout: Duration? = nil) async throws -> TrackedResponse {
        try await sendAndWaitForResponse(eventBus: eventBus, payload: (), timeout: timeout)
    }
}

public extension ResponsePayloadHandler where ResponsePayload == Void {
    /// Creates a response event with no payload.
    ///
    /// This is a convenience method for handlers that don't return data.
    ///
    /// - Returns: A `Response` event with an empty payload.
    static func response() -> Response {
        response(payload: ())
    }
}

public extension ResponseTrackedBusEventHandler where TriggerEventPayload == Void {
    /// Sends this event from within a `TrackedBusEventHandler` function and waits for the response.
    ///
    /// This is a convenience method for handlers that don't require input data.
    /// See ``sendAndWaitForResponse(inputEvent:payload:timeout:)`` for full documentation.
    ///
    /// - Parameters:
    ///   - inputEvent: The `TrackedBusEvent` that is the latest event in the chain of the `TrackedBusEventHandler` function.
    ///   - timeout: Optional timeout duration; defaults to the `EventBus` default if not specified.
    /// - Returns: The `TrackedResponse` containing the `ResponsePayload`, or `nil` if the `EventBus` has been deallocated.
    static func sendAndWaitForResponse(inputEvent: AnyTrackedBusEventType, timeout: Duration? = nil) async throws -> TrackedResponse? {
        try await sendAndWaitForResponse(inputEvent: inputEvent, payload: (), timeout: timeout)
    }

    /// Sends this event from a function that has access to an `EventBus` and waits for the response.
    ///
    /// This is a convenience method for handlers that don't require input data.
    /// See ``sendAndWaitForResponse(eventBus:payload:timeout:)`` for full documentation.
    ///
    /// - Parameters:
    ///   - eventBus: A reference to an `EventBus` into which the new event will be sent.
    ///   - timeout: Optional timeout duration; defaults to the `EventBus` default if not specified.
    /// - Returns: The `TrackedResponse` containing the `ResponsePayload`.
    static func sendAndWaitForResponse(eventBus: EventBus, timeout: Duration? = nil) async throws -> TrackedResponse {
        try await sendAndWaitForResponse(eventBus: eventBus, payload: (), timeout: timeout)
    }
}

public extension ResponseTrackedBusEventHandler where ResponsePayload == Void {
    /// Creates a response event with no payload.
    ///
    /// This is a convenience method for handlers that don't return data.
    ///
    /// - Returns: A `Response` event with an empty payload.
    static func response() -> Response {
        response(payload: ())
    }
}
