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

@testable import EventBus
import Foundation
import Testing

// swiftlint:disable no_magic_numbers
// A helper spy that wraps the real EventBusLogger to capture its output
private final class EventBusLoggerWrapper: @unchecked Sendable, EventBusLoggable {
    typealias EventType = Equatable & Sendable
    typealias Payload = Sendable

    private let realLogger: EventBusLogger
    private(set) var loggedSendColor = false
    private(set) var loggedEnteredFoodCritique = false
    private(set) var loggedExitedCritique = false
    private(set) var loggedRespondedFoodCritique = false

    init(
        logPoints: [any LogPointable] = [],
        tag: String = "eventBus",
        date: @escaping () -> Date = { .now }
    ) {
        // Initialize the actual EventBusLogger under test
        realLogger = EventBusLogger(logPoints: logPoints, tag: tag, date: date)
    }

    func log(
        _ trackedEvent: AnyTrackedBusEventType,
        as logPoint: LogPointType
    ) -> String? {
        let erasedTrackedBusEvent = ErasedTrackedBusEvent(
            eventHistory: trackedEvent.eventHistory, busEvent: trackedEvent.busEvent, eventBus: trackedEvent.eventBusCallback
        )
        guard let str = realLogger.log(erasedTrackedBusEvent, as: logPoint) else {
            return nil
        }
        recordExpectedLogHit(str)
        return str
    }

    func log(
        _ erasedEvent: ErasedTrackedBusEvent,
        as logPoint: LogPointType
    ) -> String? {
        guard let str = realLogger.log(erasedEvent, as: logPoint) else {
            return nil
        }
        recordExpectedLogHit(str)
        return str
    }

    private func recordExpectedLogHit(_ log: String) {
        if log.contains(EventBusLoggerTests.logPointPayloads[0]) {
            loggedSendColor = true
        }
        if log.contains(EventBusLoggerTests.logPointPayloads[1]) {
            loggedEnteredFoodCritique = true
        }
        if log.contains(EventBusLoggerTests.logPointPayloads[2]) {
            loggedExitedCritique = true
        }
        if log.contains(EventBusLoggerTests.logPointPayloads[3]) {
            loggedRespondedFoodCritique = true
        }
    }
}

private typealias LoggerFlowPayload = ColorAndFood

private enum LoggerControllerEvent {
    enum GetColoredFoodCritique: RequestResponseTrackedBusEventHandler {
        typealias ResponsePayload = ColoredFoodSuccess
        static let serviceName = "coloredFoodCritiqueService"
    }
}

private enum LoggerColorEvent {
    enum GetColor: RequestResponsePayloadHandler {
        typealias ResponsePayload = String
        static let serviceName = "colorApiService"
    }
}

private enum LoggerFoodEvent {
    enum GetFood: RequestResponsePayloadHandler {
        typealias RequestPayload = String
        typealias ResponsePayload = LoggerFlowPayload
        static let serviceName = "foodApiService"
    }
}

private enum LoggerCritiqueEvent {
    enum GetCritique: RequestResponsePayloadHandler {
        typealias RequestPayload = LoggerFlowPayload
        typealias ResponsePayload = String
        static let serviceName = "critiqueApiService"
    }
}

private struct LoggerFoodService: Sendable {
    @Sendable func handle(_ color: String) async throws -> LoggerFlowPayload {
        LoggerFlowPayload(color: color, food1: "Eggs", food2: nil)
    }
}

private struct LoggerCritiqueService: Sendable {
    @Sendable func handle(_ payload: LoggerFlowPayload) async throws -> String {
        "\(payload.color) \(payload.food1) sounds memorable."
    }
}

private enum LoggerCoverageConstants {
    static let eventType = "loggerFallbackEvent"
    static let actualPayload = "payload that should not format"
    static let unusedFormattedPayload = "formatter should not be used"
    static let nilPayloadLogLine = "-- Payload: Nil"
    static let errorDescription = "Synthetic logger failure"
    static let eventSequenceIndex: EventSequenceIndex = 41
}

private enum LoggerCoverageError: LocalizedError {
    case expected

    var errorDescription: String? {
        LoggerCoverageConstants.errorDescription
    }
}

@Sendable
private func loggerControllerHandler(
    _ inputEvent: LoggerControllerEvent.GetColoredFoodCritique.TrackedRequest
) async throws -> LoggerControllerEvent.GetColoredFoodCritique.TrackedResponse? {
    let timeout: Duration = .seconds(1)

    guard let colorResponse = try await LoggerColorEvent.GetColor.sendAndWaitForResponse(
        inputEvent: inputEvent,
        timeout: timeout
    ) else {
        return nil
    }

    guard let foodResponse = try await LoggerFoodEvent.GetFood.sendAndWaitForResponse(
        inputEvent: colorResponse,
        payload: colorResponse.busEvent.payload,
        timeout: timeout
    ) else {
        return nil
    }

    guard let critiqueResponse = try await LoggerCritiqueEvent.GetCritique.sendAndWaitForResponse(
        inputEvent: foodResponse,
        payload: foodResponse.busEvent.payload,
        timeout: timeout
    ) else {
        return nil
    }

    return await inputEvent.appendEvent(
        LoggerControllerEvent.GetColoredFoodCritique.response(
            payload: ColoredFoodSuccess(
                colorAndFood: foodResponse.busEvent.payload,
                critique: critiqueResponse.busEvent.payload
            )
        )
    )
}

@Suite("EventBus logger tests")
struct EventBusLoggerTests {
    static let logPointPayloads = ["sendColor", "enteredFoodCritique", "exitedCritique", "respondedFoodCritique"]

    @Test
    func controllerFlowLogging() async throws {
        // Arrange: create a spy logger configured for key log points
        let logPoints: [any LogPointable] = [
            LogPoint(
                logPointType: .sent,
                eventType: LoggerColorEvent.GetColor.requestID,
                formatPayload: { (_: Void) in EventBusLoggerTests.logPointPayloads[0]
                }
            ),
            LogPoint(
                logPointType: .enteredHandler,
                eventType: LoggerFoodEvent.GetFood.requestID,
                formatPayload: { (_: String) in EventBusLoggerTests.logPointPayloads[1] }
            ),
            LogPoint(
                logPointType: .exitedHandler,
                eventType: LoggerCritiqueEvent.GetCritique.requestID,
                formatPayload: { (_: LoggerFlowPayload) in EventBusLoggerTests.logPointPayloads[2] }
            ),
            LogPoint(
                logPointType: .responded,
                eventType: LoggerControllerEvent.GetColoredFoodCritique.responseID,
                formatPayload: { (_: ColoredFoodSuccess) in EventBusLoggerTests.logPointPayloads[3] }
            ),
        ]
        let tag: String = "eventBus"
        let date = createStaticDate()
        let spyLogger = EventBusLoggerWrapper(logPoints: logPoints, tag: tag, date: { date })

        // Inject spy into EventStream and EventBus
        let eventBus = EventBus(eventBusLogger: spyLogger)

        let colorApiService = ColorSelectionService()
        let foodApiService = LoggerFoodService()
        eventBus.register(
            handlers: [
                LoggerColorEvent.GetColor.handlerRegistration {
                    try await colorApiService.selectColor()
                },
                LoggerFoodEvent.GetFood.handlerRegistration(foodApiService.handle),
                LoggerCritiqueEvent.GetCritique.handlerRegistration(LoggerCritiqueService().handle),
                LoggerControllerEvent.GetColoredFoodCritique.handlerRegistration(loggerControllerHandler),
            ]
        )

        let _: LoggerControllerEvent.GetColoredFoodCritique.TrackedResponse = try await LoggerControllerEvent.GetColoredFoodCritique.sendAndWaitForResponse(
            eventBus: eventBus,
            timeout: .seconds(1)
        )

        #expect(spyLogger.loggedSendColor)
        #expect(spyLogger.loggedEnteredFoodCritique)
        #expect(spyLogger.loggedExitedCritique)
        #expect(spyLogger.loggedRespondedFoodCritique)
    }

    @Test
    func directLoggerCoversFallbackFormattingAndErrorOutput() {
        let event = BusEvent(
            eventType: LoggerCoverageConstants.eventType,
            payload: LoggerCoverageConstants.actualPayload
        )
        let logPoint = LogPoint(
            logPointType: .errored(LoggerCoverageError.expected),
            eventType: LoggerCoverageConstants.eventType,
            formatPayload: { (_: Int) in LoggerCoverageConstants.unusedFormattedPayload }
        )
        let logger = EventBusLogger(
            logPoints: [logPoint],
            tag: "eventBus",
            date: { createStaticDate() }
        )
        let trackedEvent = ErasedTrackedBusEvent(
            eventHistory: [
                BusEventProcessStepRecord(
                    busEvent: event,
                    stepType: .handlerError,
                    eventSequenceIndex: LoggerCoverageConstants.eventSequenceIndex
                ),
            ],
            busEvent: event,
            eventBus: nil
        )

        let log = logger.log(trackedEvent, as: .errored(LoggerCoverageError.expected))

        #expect(log?.contains(LoggerCoverageConstants.eventType) == true)
        #expect(log?.contains(LoggerCoverageConstants.nilPayloadLogLine) == true)
        #expect(log?.contains(LoggerCoverageConstants.errorDescription) == true)
        #expect(log?.contains(LoggerCoverageConstants.unusedFormattedPayload) == false)
    }

    func createStaticDate() -> Date {
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 1
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(from: components)!
    }
}

// swiftlint:enable no_magic_numbers
