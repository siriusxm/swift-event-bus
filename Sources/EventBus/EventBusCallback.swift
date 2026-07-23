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

/// Represents the EventBus for event handlers that call back into the bus to invoke more events and optionally wait for responses and/or chain events into related processes.
public protocol EventBusCallback: Sendable {
    var defaultTimeout: Duration { get }

    /// Cancels ongoing operations in handlers that match the provided input event.
    ///
    /// - Parameter event: Only operations matching this event will be cancelled.
    func cancelHandlers(for event: any Equatable & Sendable) async

    /// Sends an event into the bus without waiting for a response.
    /// - Parameters:
    ///   - event: a BusEventType object or struct, which contains the eventType identifier and the payload data.
    ///            both must match a handler registered to the bus for this to be handled, otherwise it will be ignored
    /// - Returns: nothing
    func send(_ event: BusEvent<some Equatable & Sendable, some Sendable>) async

    /// Sends an event into the bus without waiting for a response, and appends event tracking to a previous event history.
    /// - Parameters:
    ///   - previousEvent: the event record of the previous event chain to which you want to add the current event's processing
    ///   - event: a BusEventType object or struct, which contains the eventType identifier and the payload data.
    ///            both must match a handler registered to the bus for this to be handled, otherwise it will be ignored
    func send(_ previousEvent: AnyTrackedBusEventType, _ event: BusEvent<some Equatable & Sendable, some Sendable>) async

    /// Sends an event into the bus and waits for a matching response, starting a new event tracking history.
    /// - Parameters:
    ///   - inputEvent: the current event's type identifier
    ///   - resultType: the expected result event's type identifier
    ///   - matchingOptions: array of options for the result to match to satisfy this function
    ///   - timeout: the duration the sender is allowing for the expected response before throwing a timeout error
    /// - Returns: if successful, a TrackedBusEvent wrapping the expected response type
    ///            (note that because of swift generic requirements, you will probably have to explicitly type the return statement)
    ///            if error, this will throw an error of type EventBusError.timeoutError
    func sendAndWaitForMatchingResult<
        ResultEventType: Equatable & Sendable,
        ResultPayload: Sendable
    >
    (
        _ inputEvent: BusEvent<some Equatable & Sendable, some Sendable>,
        resultType: ResultEventType,
        matchingOptions: [BusEventMatchingOption],
        timeout: Duration
    ) async throws -> TrackedBusEvent<ResultEventType, ResultPayload>

    /// Sends an event into the bus and waits for a matching response, appending event tracking to a previous event's history.
    /// - Parameters:
    ///   - previousEvent: the event record of the previous event chain to which you want to add the current event's processing
    ///   - inputEvent: the current event's type identifier
    ///   - resultType: the expected result event's type identifier
    ///   - matchingOptions: array of options for the result to match to satisfy this function
    ///   - timeout: the duration the sender is allowing for the expected response before throwing a timeout error
    /// - Returns: if successful, a TrackedBusEvent wrapping the expected response type
    ///            (note that because of swift generic requirements, you will probably have to explicitly type the return statement)
    ///            if error, this will throw an error of type EventBusError.timeoutError
    func sendAndWaitForMatchingResult<
        ResultEventType: Equatable & Sendable,
        ResultPayload: Sendable
    >(
        _ previousEvent: AnyTrackedBusEventType,
        _ inputEvent: BusEvent<some Equatable & Sendable, some Sendable>,
        resultType: ResultEventType,
        matchingOptions: [BusEventMatchingOption],
        timeout: Duration
    ) async throws -> TrackedBusEvent<ResultEventType, ResultPayload>

    /// Creates a tracked bus event with the given history, allowing handlers to sendAndWait to other handlers
    /// ...and accumulate the history of those calls into an intermediate result that will be completed later in the handler.
    /// - Parameters:
    ///   - previousEvent: the event record of the previous event chain to which you want to add the current result event's processing
    ///   - event: a BusEventType object or struct, which contains the eventType identifier and the payload data for the result event
    /// - Returns: the event packaged in a TrackedBusEvent with its history
    func trackedBusEvent<EventType: Equatable & Sendable, Payload: Sendable>(
        _ previousEvent: AnyTrackedBusEventType,
        _ event: BusEvent<EventType, Payload>
    ) async -> TrackedBusEvent<EventType, Payload>
}
