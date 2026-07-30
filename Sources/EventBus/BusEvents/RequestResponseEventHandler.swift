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

// swiftlint:disable file_length

/// Base protocol for declaring unique dedicated request and response events for a handler function.
/// Use derived ``RequestResponsePayloadHandler`` or ``RequestResponseTrackedBusEventHandler`` to actually declare events.
public protocol RequestResponseEventHandler<RequestPayload, ResponsePayload>: Sendable {
    associatedtype RequestPayload: Sendable = Void
    associatedtype ResponsePayload: Sendable = Void

    static var concurrencyType: EventBus.ConcurrencyType { get }
    static var serviceName: ServiceName { get }
}

public extension RequestResponseEventHandler {
    typealias RequestEvent = RequestResponseRequestEvent<Self, RequestPayload>
    typealias ResponseEvent = RequestResponseResponseEvent<Self, ResponsePayload>

    typealias Request = RequestEvent.Event
    typealias TrackedRequest = RequestEvent.TrackedEvent
    typealias Response = ResponseEvent.Event
    typealias TrackedResponse = ResponseEvent.TrackedEvent

    static var concurrencyType: EventBus.ConcurrencyType { .parallel }
    static var serviceName: ServiceName { "Default Name" }

    /// Used internally, for logging, and for cancelling requests.
    static var requestID: ObjectIdentifier {
        RequestEvent.eventType
    }

    /// Used internally, for logging, and for cancelling requests.
    static var responseID: ObjectIdentifier {
        ResponseEvent.eventType
    }

    /// Used interrnally, and for manually creating a request event.
    ///
    /// For most cases `send` and `sendAndWaitForResponse` functions will create requests for you.
    ///
    /// - Parameter payload: The `RequestPayload` data defined for the `Request` event.
    /// - Returns: A `Request` event created from the provided payload.
    static func request(payload: RequestPayload) -> Request {
        RequestEvent.event(payload: payload)
    }

    /// Creates a response event for use by `TrackedBusEventHandler` functions.
    ///
    /// This helper wraps the given `ResponsePayload` into a `Response` that the `EventBus` will publish after the handler function returns.
    ///
    /// - Parameter payload: The the data returned by the handler function to pass into the `Response` event.
    /// - Returns: A `Response` event created from the provided payload.
    static func response(payload: ResponsePayload) -> Response {
        ResponseEvent.event(payload: payload)
    }

    /// Sends this event from within a `TrackedBusEventHandler` function without waiting for a response.
    ///
    /// This variant uses an `inputEvent` available in a `TrackedBusEventHandler` function to create and send a side-effect event,
    /// that branches off into a separate event chain. The resulting event can't be chained into the current handler function's result event history,
    /// and this `send` function will return immediately before this new event is handled.
    /// Use `sendAndWaitForResponse` to chain events into the handler results.
    ///
    /// - Parameters:
    ///   - inputEvent: The `TrackedBusEvent` that is the latest event in the chain of the `TrackedBusEventHandler` function.
    ///   - payload: The `RequestPayload` data defined for the `RequestEvent` input event.
    static func send(inputEvent: AnyTrackedBusEventType, payload: RequestPayload) async {
        await inputEvent.eventBusCallback?.send(inputEvent, request(payload: payload))
    }

    /// Sends this event from a function that has access to an `EventBus` without waiting for a response.
    ///
    /// This variant uses a reference to the `EventBus` to create and broadcast an event into the bus without waiting for a response.
    /// This `send` function will return immediately before this new event is handled, and the resulting event will start a new event chain in the bus.
    /// Use `sendAndWaitForResponse` to wait for the request-response pair's `ResponseEvent` and insure the requested operation is complete.
    ///
    /// - Parameters:
    ///   - eventBus: A reference to an `EventBus` into which the new event will be sent.
    ///   - payload: The `RequestPayload` data defined for the `RequestEvent` to be created.
    static func send(eventBus: EventBus, payload: RequestPayload) async {
        await eventBus.send(request(payload: payload))
    }
}

/// Declares unique dedicated request and response events for a handler function that takes and returns simple payloads, or void handler functions.
/// Payload types are defaulted to Void if not specified in the type declaration.
public protocol RequestResponsePayloadHandler: RequestResponseEventHandler {
    typealias HandlerType = @Sendable (RequestPayload) async throws -> ResponsePayload
}

public extension RequestResponsePayloadHandler {
    /// Returns a registration record for a handler function that processes this event type.
    ///
    /// This method wraps a simple handler function or closure that takes a `RequestPayload` and returns a `ResponsePayload`
    /// into an `EventBusHandler` record suitable for registration with an `EventBus`.
    /// The handler is automatically wrapped to convert its `ResponsePayload` into a `Response` event.
    ///
    /// - Parameter handler: A function or closure that receives a `RequestPayload` and asynchronously returns a `ResponsePayload`.
    /// - Returns: An `EventBusHandler` record that can be passed to the `EventBus` `register` function.
    @Sendable static func handlerRegistration(
        _ handler: @escaping HandlerType
    ) -> EventBusHandler<ObjectIdentifier, RequestPayload> {
        let handlerAdapter: @Sendable (RequestPayload) async throws -> [Self.Response] = { payload in
            let responsePayload = try await handler(payload)
            return [response(payload: responsePayload)]
        }

        return EventBusHandler(
            concurrencyType,
            handler: handlerAdapter,
            eventType: requestID,
            serviceName: serviceName
        )
    }

    /// Sends this event from within a `TrackedBusEventHandler` function and waits for the response.
    ///
    /// This variant uses the latest event that is available in a `TrackedBusEventHandler` function to create and send a `RequestEvent`,
    /// then awaits the corresponding `TrackedResponse` event. The `inputEvent` history is automatically chained into the response.
    /// This function will  return `nil` if the `EventBus` has been deallocated while the handler function is still asynchronously running.
    /// So `TrackedBusEventHandler` functions should immediately return `nil` on receiving a `nil` from this function with no further processing.
    /// Use `send` if you do not need to wait for or track the response.
    ///
    /// - Parameters:
    ///   - inputEvent: The `TrackedBusEvent` that is the latest event in the chain of the `TrackedBusEventHandler` function.
    ///   - payload: The `RequestPayload` data defined for the `RequestEvent`.
    ///   - timeout: Optional timeout duration; defaults to the `EventBus` default if not specified.
    /// - Returns: The `TrackedResponse` containing the `ResponsePayload`, or `nil` if the `EventBus` has been deallocated.
    static func sendAndWaitForResponse(
        inputEvent: AnyTrackedBusEventType,
        payload: RequestPayload,
        timeout: Duration? = nil
    ) async throws -> TrackedResponse? {
        try await inputEvent.eventBusCallback?.sendAndWaitForMatchingResult(
            inputEvent,
            request(payload: payload),
            resultType: responseID,
            matchingOptions: [.matchResponse(.direct)],
            timeout: timeout ?? inputEvent.eventBusCallback?.defaultTimeout ?? .zero
        )
    }

    /// Sends this event from a function that has access to an `EventBus` and waits for the response.
    ///
    /// This variant uses a reference to the `EventBus` to create and send a `RequestEvent`, then awaits the corresponding `ResponseEvent`.
    /// The resulting event starts a new event chain in the bus. Use `send` if you do not need to wait for a response.
    ///
    /// - Parameters:
    ///   - eventBus: A reference to an `EventBus` into which the new event will be sent.
    ///   - payload: The `RequestPayload` data defined for the `RequestEvent` to be created.
    ///   - timeout: Optional timeout duration; defaults to the `EventBus` default if not specified.
    /// - Returns: The `TrackedResponse` containing the `ResponsePayload`.
    static func sendAndWaitForResponse(
        eventBus: EventBus,
        payload: RequestPayload,
        timeout: Duration? = nil
    ) async throws -> TrackedResponse {
        try await eventBus.sendAndWaitForMatchingResult(
            request(payload: payload),
            resultType: responseID,
            matchingOptions: [.matchResponse(.direct)],
            timeout: timeout ?? eventBus.defaultTimeout
        )
    }
}

/// Declares unique dedicated request and response events for a handler function that posts additional events back into the EventBus.
/// Payload types are defaulted to Void if not specified in the type declaration.
public protocol RequestResponseTrackedBusEventHandler: RequestResponseEventHandler {
    typealias HandlerType = @Sendable (TrackedRequest) async throws -> TrackedResponse?
}

public extension RequestResponseTrackedBusEventHandler {
    /// Returns a registration record for a handler function that processes this event type.
    ///
    /// This method wraps a handler function or closure that takes a `TrackedRequest` and returns a `TrackedResponse?`
    /// into an `EventBusHandler` record suitable for registration with an `EventBus`.
    /// The handler function receives a `TrackedRequest`event, allowing it to send additional events into the bus and chain event histories.
    ///
    /// - Parameter handler: A function or closure that receives a `TrackedRequest` and asynchronously returns a `TrackedResponse?`.
    /// - Returns: An `EventBusHandler` record that can be passed to the `EventBus` `register` function.
    @Sendable static func handlerRegistration(
        _ handler: @escaping HandlerType
    ) -> EventBusHandler<ObjectIdentifier, RequestPayload> {
        let trackedBusEventHandler: @Sendable (TrackedRequest) async throws -> [AnyTrackedBusEventType?]? = { inputEvent in
            try await [handler(inputEvent)]
        }

        return EventBusHandler(
            concurrencyType,
            trackedBusEventHandler: trackedBusEventHandler,
            eventType: RequestEvent.eventType,
            serviceName: serviceName
        )
    }

    /// Sends this event from within a `TrackedBusEventHandler` function and waits for the response.
    ///
    /// This variant uses the latest event that is available in a `TrackedBusEventHandler` function to create and send a request event,
    /// then awaits the corresponding `TrackedResponse` event. The `inputEvent` history is automatically chained into the response.
    /// This function will return `nil` if the `EventBus` has been deallocated while the handler function is still asynchronously running.
    /// So `TrackedBusEventHandler` functions should immediately return `nil` on receiving a `nil` from this function with no further processing.
    /// Use `send` if you do not need to wait for or track the response.
    ///
    /// - Parameters:
    ///   - inputEvent: The `TrackedBusEvent` that is the latest event in the chain of the `TrackedBusEventHandler` function.
    ///   - payload: The `RequestPayload` data defined for the `RequestEvent`.
    ///   - timeout: Optional timeout duration; defaults to the `EventBus` default if not specified.
    /// - Returns: The `TrackedResponse` containing the `ResponsePayload`, or `nil` if the `EventBus` has been deallocated.
    static func sendAndWaitForResponse(
        inputEvent: AnyTrackedBusEventType,
        payload: RequestPayload,
        timeout: Duration? = nil
    ) async throws -> TrackedResponse? {
        try await inputEvent.eventBusCallback?.sendAndWaitForMatchingResult(
            inputEvent,
            request(payload: payload),
            resultType: responseID,
            matchingOptions: [.matchResponse(.indirect)],
            timeout: timeout ?? inputEvent.eventBusCallback?.defaultTimeout ?? .zero
        )
    }

    /// Sends this event from a function that has access to an `EventBus` and waits for the response.
    ///
    /// This variant uses a reference to the `EventBus` to create and send a `RequestEvent`, then awaits the corresponding `ResponseEvent`.
    /// The resulting event starts a new event chain in the bus.
    /// Use `send` if you do not need to wait for a response.
    ///
    /// - Parameters:
    ///   - eventBus: A reference to an `EventBus` into which the new event will be sent.
    ///   - payload: The `RequestPayload` data defined for the `RequestEvent` to be created.
    ///   - timeout: Optional timeout duration; defaults to the `EventBus` default if not specified.
    /// - Returns: The `TrackedResponse` containing the `ResponsePayload`.
    static func sendAndWaitForResponse(
        eventBus: EventBus,
        payload: RequestPayload,
        timeout: Duration? = nil
    ) async throws -> TrackedResponse {
        try await eventBus.sendAndWaitForMatchingResult(
            request(payload: payload),
            resultType: responseID,
            matchingOptions: [.matchResponse(.indirect)],
            timeout: timeout ?? eventBus.defaultTimeout
        )
    }
}

// MARK: - Void Payload Conveniences

public extension RequestResponsePayloadHandler where RequestPayload == Void {
    /// Used internally, and for manually creating a request event with no payload.
    ///
    /// For most cases `send` and `sendAndWaitForResponse` functions will create requests for you.
    ///
    /// - Returns: A `Request` event with an empty payload.
    static func request() -> Request {
        request(payload: ())
    }

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

    /// Sends this event from within a `TrackedBusEventHandler` function without waiting for a response.
    ///
    /// This is a convenience method for handlers that don't require input data.
    /// See ``RequestResponseEventHandler/send(inputEvent:payload:)`` for full documentation.
    ///
    /// - Parameter inputEvent: The `TrackedBusEvent` that is the latest event in the chain of the `TrackedBusEventHandler` function.
    static func send(inputEvent: AnyTrackedBusEventType) async {
        await send(inputEvent: inputEvent, payload: ())
    }

    /// Sends this event from a function that has access to an `EventBus` without waiting for a response.
    ///
    /// This is a convenience method for handlers that don't require input data.
    /// See ``RequestResponseEventHandler/send(eventBus:payload:)`` for full documentation.
    ///
    /// - Parameter eventBus: A reference to an `EventBus` into which the new event will be sent.
    static func send(eventBus: EventBus) async {
        await send(eventBus: eventBus, payload: ())
    }
}

public extension RequestResponsePayloadHandler where ResponsePayload == Void {
    /// Creates a response event with no payload.
    ///
    /// This is a convenience method for handlers that don't return data.
    ///
    /// - Returns: A `Response` event with an empty payload.
    static func response() -> Response {
        response(payload: ())
    }
}

public extension RequestResponseTrackedBusEventHandler where RequestPayload == Void {
    /// Used internally, and for manually creating a request event with no payload.
    ///
    /// For most cases `send` and `sendAndWaitForResponse` functions will create requests for you.
    ///
    /// - Returns: A `Request` event with an empty payload.
    static func request() -> Request {
        request(payload: ())
    }

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

    /// Sends this event from within a `TrackedBusEventHandler` function without waiting for a response.
    ///
    /// This is a convenience method for handlers that don't require input data.
    /// See ``RequestResponseEventHandler/send(inputEvent:payload:)`` for full documentation.
    ///
    /// - Parameter inputEvent: The `TrackedBusEvent` that is the latest event in the chain of the `TrackedBusEventHandler` function.
    static func send(inputEvent: AnyTrackedBusEventType) async {
        await send(inputEvent: inputEvent, payload: ())
    }

    /// Sends this event from a function that has access to an `EventBus` without waiting for a response.
    ///
    /// This is a convenience method for handlers that don't require input data.
    /// See ``RequestResponseEventHandler/send(eventBus:payload:)`` for full documentation.
    ///
    /// - Parameter eventBus: A reference to an `EventBus` into which the new event will be sent.
    static func send(eventBus: EventBus) async {
        await send(eventBus: eventBus, payload: ())
    }
}

public extension RequestResponseTrackedBusEventHandler where ResponsePayload == Void {
    /// Creates a response event with no payload.
    ///
    /// This is a convenience method for handlers that don't return data.
    ///
    /// - Returns: A `Response` event with an empty payload.
    static func response() -> Response {
        response(payload: ())
    }
}

// MARK: - Internal definitions for request and response

public struct RequestResponseRequestEvent<Factory: Sendable, P: Sendable>: SimpleBusEventType {
    public typealias Payload = P

    public static var debugName: String {
        String(reflecting: Factory.self) + ".Request"
    }
}

public struct RequestResponseResponseEvent<Factory: Sendable, P: Sendable>: SimpleBusEventType {
    public typealias Payload = P

    public static var debugName: String {
        String(reflecting: Factory.self) + ".Response"
    }
}

// swiftlint:enable file_length
