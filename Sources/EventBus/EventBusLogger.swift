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

/// A logging interface for events processed by the EventBus.
/// Allows conditional logging based on log points (e.g., sent, responded, errored).
public protocol EventBusLoggable: Sendable {
    @discardableResult
    func log(
        _ trackedEvent: AnyTrackedBusEventType,
        as logPoint: LogPointType
    ) -> String?
    @discardableResult
    func log(
        _ erasedEvent: ErasedTrackedBusEvent,
        as logPoint: LogPointType
    ) -> String?
}

/// Concrete logger implementation for EventBus events.
/// Filters which points in an event's lifecycle to log based on configured logPoints.
public struct EventBusLogger: EventBusLoggable {
    // MARK: - Properties

    /// The set of log points that should be logged.
    private let logPoints: [LogPointKey: AnyLogPoint]

    /// The tag attached to every log for filtering/searching.
    public let tag: String

    /// Fixed point in time when the logger was instantiated.
    private let date: Date

    public init(
        logPoints: [any LogPointable] = [],
        tag: String = "eventBus",
        date: @escaping () -> Date = { .now }
    ) {
        var dictionary: [LogPointKey: AnyLogPoint] = [:]

        for point in logPoints {
            let key = LogPointKey(eventType: point.eventType, logPointType: point.logPointType)
            dictionary[key] = AnyLogPoint(point)
        }

        self.logPoints = dictionary
        self.tag = tag
        self.date = date()
    }

    // MARK: - Public Logging Interface

    @discardableResult
    public func log(
        _ erasedEvent: ErasedTrackedBusEvent,
        as logPoint: LogPointType
    ) -> String? {
        guard
            let busEventProcessRecord = erasedEvent.eventHistory.last,
            shouldLog(eventType: erasedEvent.busEvent.eventType, logPointType: logPoint)
        else {
            return nil
        }

        let logString = buildLogString(
            logPoint: logPoint,
            busEvent: erasedEvent.busEvent,
            sequence: String(busEventProcessRecord.eventSequenceIndex),
            stepType: String(describing: busEventProcessRecord.stepType),
            payload: erasedEvent.busEvent.payload
        )

        logger.info("\(logString)", tag: tag)
        return logString
    }

    @discardableResult
    public func log(
        _ trackedEvent: AnyTrackedBusEventType,
        as logPoint: LogPointType
    ) -> String? {
        guard
            let busEventProcessRecord = trackedEvent.eventHistory.last,
            shouldLog(eventType: trackedEvent.busEvent.eventType, logPointType: logPoint)
        else {
            return nil
        }

        let logString = buildLogString(
            logPoint: logPoint,
            busEvent: trackedEvent.busEvent,
            sequence: String(busEventProcessRecord.eventSequenceIndex),
            stepType: String(describing: busEventProcessRecord.stepType),
            payload: trackedEvent.busEvent.payload
        )

        logger.info("\(logString)", tag: tag)
        return logString
    }

    // MARK: - Formatting

    /// Builds a structured log string with details about the event lifecycle and payload.
    private func buildLogString(
        logPoint: LogPointType,
        busEvent: any BusEventType,
        sequence: String,
        stepType: String,
        payload: Any
    ) -> String {
        let eventTypeString = busEvent.debugName ?? String(reflecting: busEvent.eventType)
        let formattedPayload = formatPayload(payload: payload, eventType: busEvent.eventType, logPointType: logPoint) ?? "Nil"
        let errorString = if case let .errored(error) = logPoint {
            error.localizedDescription
        } else {
            "Nil"
        }

        return """
        \n\(tag)---------------------------------------\(tag)
        -- LogPoint: \(logPoint.emoji) \(logPoint.description)
        -- Event Type: \(eventTypeString)
        -- Event Sequence Index: \(sequence)
        -- Step Type: \(stepType)
        -- Payload: \(formattedPayload)
        -- Error: \(errorString)
        -- Log Timestamp: \(date)
        """
    }

    // MARK: - Payload Formatting Helper

    /// Attempts to apply a custom formatter to the payload based on configured log points.
    private func formatPayload(payload: Any, eventType: Any, logPointType: LogPointType) -> String? {
        let key = LogPointKey(eventType: eventType, logPointType: logPointType)
        return logPoints[key]?.formatPayloadIfPossible(payload: payload)
    }

    // MARK: - Logic

    /// Checks whether a given log point type should be logged according to the configuration.
    public func shouldLog(eventType: Any, logPointType: LogPointType) -> Bool {
        let key = LogPointKey(eventType: eventType, logPointType: logPointType)
        return logPoints[key] != nil
    }
}
