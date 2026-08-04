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

// Using UInt64 as the event sequence index.
// At one million events per second, UInt64 will take over 300 thousand years to overflow
// so this code considers UInt64 overflow-proof and assumes it can always increase the currentValue
public typealias EventSequenceIndex = UInt64

// MARK: - EventBusCallback conformance

// This includes all functions used from inside registered EventBus handler functions that call back into the EventBus,
// as well as the send functions to send events into the EventBus from any code.

// swiftformat:disable opaqueGenericParameters
extension EventBus: EventBusCallback {
    /// Cancels ongoing operations in handlers that match the provided input event.
    ///
    /// - Parameter event: Only operations matching this event will be cancelled.
    public func cancelHandlers(for event: any Equatable & Sendable) async {
        handlingInstances.cancelHandlingTasks(for: event)
    }

    /// Sends an event into the bus without returning an event handling response.
    /// - Parameters:
    ///   - event: a BusEventType object or struct, which contains the eventType identifier and the payload data.
    ///            both must match a handler registered to the bus for this to be handled, otherwise it will be ignored
    public func send(_ event: BusEvent<some Equatable & Sendable, some Sendable>) async {
        let history = history(with: event, and: nil)
        await send(event, history)
    }

    /// Sends an event into the bus without waiting for a response, and appends event tracking to a previous event's history.
    ///
    /// - Parameters:
    ///   - previousEvent: The event record of the previous event chain to which you want to add the current event's processing.
    ///   - event: A `BusEventType` object or struct containing the `eventType` identifier and the payload data.
    ///     Both must match a handler registered to the bus for this to be handled, otherwise it will be ignored.
    public func send(_ previousEvent: AnyTrackedBusEventType, _ event: BusEvent<some Equatable & Sendable, some Sendable>) async {
        let history = history(with: event, and: previousEvent)
        await send(event, history)
    }

    /// Sends an event into the bus and waits for a matching response, starting a new event tracking history.
    /// - Parameters:
    ///   - inputEvent: the current event's type identifier
    ///   - resultType: the expected result event's type identifier
    ///   - matchingOptions: array of options for the result to match to satisfy this function
    ///   - timeout: the duration the sender is allowing for the expected response before throwing a timeout error
    /// - Returns: if successful, a TrackedBusEvent wrapping the expected response type
    ///            (note that because of swift generic requirements, you will probably have to explicitly type the return statement)
    ///            if error, this will throw an error of type EventBusError
    public func sendAndWaitForMatchingResult<
        ResultEventType: Equatable & Sendable,
        ResultPayload: Sendable
    >(
        _ inputEvent: BusEvent<some Equatable & Sendable, some Sendable>,
        resultType: ResultEventType,
        matchingOptions: [BusEventMatchingOption],
        timeout: Duration
    ) async throws -> TrackedBusEvent<ResultEventType, ResultPayload> {
        try await _sendAndWaitForMatchingResult(
            nil,
            inputEvent,
            resultType: resultType,
            matchingOptions: matchingOptions,
            timeout: timeout
        )
    }

    /// Sends an event into the bus and waits for a matching response, appending event tracking to a previous event's history.
    /// - Parameters:
    ///   - previousEvent: The event record of the previous event chain to which you want to add the current event's processing.
    ///   - inputEvent: The input event to send into the bus.
    ///   - resultType: The expected result event's type identifier.
    ///   - matchingOptions: Array of options for the result to match to satisfy this function.
    ///   - timeout: The duration the sender is allowing for the expected response before throwing a timeout error.
    /// - Returns: A `TrackedBusEvent` wrapping the expected response type.
    /// - Throws: `EventBusError.timeoutError` if the response is not received within the specified timeout, or other error thrown by the handler.
    /// - Note: Due to Swift generic requirements, you may need to explicitly type the return value.
    public func sendAndWaitForMatchingResult<
        ResultEventType: Equatable & Sendable, ResultPayload: Sendable
    >(
        _ previousEvent: AnyTrackedBusEventType,
        _ inputEvent: BusEvent<some Equatable & Sendable, some Sendable>,
        resultType: ResultEventType,
        matchingOptions: [BusEventMatchingOption],
        timeout: Duration
    ) async throws -> TrackedBusEvent<ResultEventType, ResultPayload> {
        try await _sendAndWaitForMatchingResult(
            previousEvent,
            inputEvent,
            resultType: resultType,
            matchingOptions: matchingOptions,
            timeout: timeout
        )
    }

    /// Creates a tracked bus event with the given history, allowing handlers to sendAndWait to other handlers and accumulate the history of those calls into an intermediate result that will be completed later in the handler.
    /// - Parameters:
    ///   - previousEvent: the event record of the previous event chain to which you want to add the current result event's processing
    ///   - event: a BusEventType object or struct, which contains the eventType identifier and the payload data for the result event
    /// - Returns: the event packaged in a TrackedBusEvent with its history
    public func trackedBusEvent<EventType: Equatable & Sendable, Payload: Sendable>(
        _ previousEvent: AnyTrackedBusEventType,
        _ event: BusEvent<EventType, Payload>
    ) -> TrackedBusEvent<EventType, Payload> {
        TrackedBusEvent<EventType, Payload>(
            eventHistory: previousEvent.eventHistory + [wrapWithStepRecord(event)],
            busEvent: event,
            eventBus: self
        )
    }
}

// MARK: - internal utilities used in EventBusCallback functions

extension EventBus {
    /// This function creates guaranteed unique positive integers that increase in a sequence of event occurrence across the EventStream.
    /// The resulting indices can be compared directly to see when they occurred in relation to each other in sequence.
    /// These indices are attached to events, so can be used to track if the events relate to each other in request/response or other ordered call-chain relationships.
    private func nextEventSequenceValue() -> EventSequenceIndex {
        currentEventSequenceValue.withValue {
            $0 += 1
            return $0
        }
    }

    func history<EventType: Equatable & Sendable, Payload: Sendable>(
        with event: any BusEventType<EventType, Payload>,
        and previousEvent: AnyTrackedBusEventType? = nil
    ) -> BusEventProcessRecord {
        let stepRecord = wrapWithStepRecord(event)
        return previousEvent.map { $0.eventHistory + [stepRecord] } ?? [stepRecord]
    }

    private func send<EventType: Equatable & Sendable, Payload: Sendable>(
        _ event: any BusEventType<EventType, Payload>,
        _ history: BusEventProcessRecord
    ) async {
        eventBusLogger?.log(history, event, as: .sent)
        subject.send(history)
    }

    // Currently the only "matching" results are direct or indirect response to the request.
    func eventMatchingStream<EventType: Equatable & Sendable, Payload: Sendable, InputEvent: BusEventType>(
        inputEvent: InputEvent,
        result eventTypeToMatch: EventType,
        requestEvent: BusEventProcessRecord,
        matchingOptions: [BusEventMatchingOption]
    ) -> AsyncThrowingStream<TrackedBusEvent<EventType, Payload>, Error> {
        subject
            .bufferedValues
            .filter { $0.matchResponseWithOptions(to: requestEvent, matchingOptions: matchingOptions) }
            .compactMap { record in
                if let typedBusEvent = record.busEvent as? any BusEventType<EventType, Payload>,
                   typedBusEvent.eventType == eventTypeToMatch
                {
                    return TrackedBusEvent(eventHistory: record, busEvent: typedBusEvent, eventBus: self)
                }

                if let errorEvent = record.busEvent as? BusErrorEvent<InputEvent.EventType>,
                   errorEvent.eventType == inputEvent.eventType
                {
                    throw errorEvent.payload
                }

                return nil
            }
            .eraseToThrowingStream()
    }

    // internal version of sendAndWait conforms to either public version
    private func _sendAndWaitForMatchingResult<
        ResultEventType: Equatable & Sendable & Equatable & Sendable,
        ResultPayload: Sendable & Sendable
    >(
        _ previousEvent: AnyTrackedBusEventType? = nil,
        _ inputEvent: BusEvent<some Equatable & Sendable, some Sendable>,
        resultType: ResultEventType,
        matchingOptions: [BusEventMatchingOption],
        timeout: Duration
    ) async throws -> TrackedBusEvent<ResultEventType, ResultPayload> {
        let history = history(with: inputEvent, and: previousEvent)
        // Subscribe to events before sending the input event
        let eventMatchingStream: AsyncThrowingStream<
            TrackedBusEvent<ResultEventType, ResultPayload>,
            Error
        > = eventMatchingStream(
            inputEvent: inputEvent,
            result: resultType,
            requestEvent: history,
            matchingOptions: matchingOptions
        )
        await send(inputEvent, history)

        return try await Task(maximumDuration: timeout) {
            for try await event in eventMatchingStream {
                try Task.checkCancellation()
                return event
            }
            throw EventBusError.timeoutError
        }
        .result
        .mapError { $0 is TaskTimeoutError ? EventBusError.timeoutError : $0 }
        .get()
    }

    func wrapWithPreviousProcessHistory(
        event: any BusEventType,
        stepType: BusEventStepType,
        historyProcessRecord: BusEventProcessRecord
    ) -> BusEventProcessRecord {
        historyProcessRecord + [BusEventProcessStepRecord(
            busEvent: event,
            stepType: stepType,
            eventSequenceIndex: nextEventSequenceValue()
        )]
    }

    // used internally in sendAndWait functions to wrap the incoming event
    // ..before it's added to the correct variation of new or continuing BusEventProcessRecord
    func wrapWithStepRecord(_ event: any BusEventType) -> BusEventProcessStepRecord {
        BusEventProcessStepRecord(
            busEvent: event,
            stepType: .requestWithSend,
            eventSequenceIndex: nextEventSequenceValue()
        )
    }
}

// swiftformat:enable opaqueGenericParameters
