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

import ConcurrencyExtras
@testable import EventBus
import Testing

// swiftlint:disable no_magic_numbers
@Suite("Event Stream Tests")
struct EventStreamTests {
    @Test
    func parallelHandlerIntegration() async throws {
        let eventBus = EventBus(defaultTimeout: EventStreamConstants.defaultTimeout)
        let testService = ColoredFoodTestService()
        registerColoredFoodHandlers(testService: testService, eventBus: eventBus)

        let responses = try await withThrowingTaskGroup(
            of: EventStreamCompleteEvent.TrackedEvent.self,
            returning: [EventStreamCompleteEvent.TrackedEvent].self
        ) { group in
            for _ in 0 ..< EventStreamConstants.maxIterations {
                group.addTask {
                    try await EventStreamColorToCompleteLink.sendAndWaitForResponse(
                        eventBus: eventBus,
                        payload: TestPayloadWithColoredFood(eventType: EventStreamConstants.colorServiceEventType),
                        timeout: EventStreamConstants.defaultTimeout
                    )
                }
            }

            var responses: [EventStreamCompleteEvent.TrackedEvent] = []
            for try await response in group {
                responses.append(response)
            }
            return responses
        }

        #expect(responses.count == EventStreamConstants.maxIterations)
        for response in responses {
            #expect(ColoredFoodTestService.isValidRecord(response.busEvent.payload.coloredFoodTestRecord))
        }

        await assertColoredFoodTestData(testService)
    }

    @Test
    func serialHandlerEventsSuccess() async throws {
        let eventBus = EventBus(defaultTimeout: EventStreamConstants.defaultTimeout)
        let result = LockIsolated<[Int]>([])
        eventBus.register(handlers: [
            EventStreamSerialHandler.handlerRegistration { value in
                try await sleepForSerialPayload(value)
                if value != EventStreamConstants.serialFlushValue {
                    result.withValue { $0.append(value) }
                }
                return EventStreamConstants.serialHandlerOutputValue
            },
        ])

        for int in EventStreamConstants.serialInputValues {
            await EventStreamSerialHandler.send(eventBus: eventBus, payload: int)
        }

        let response = try await EventStreamSerialHandler.sendAndWaitForResponse(
            eventBus: eventBus,
            payload: EventStreamConstants.serialFlushValue,
            timeout: EventStreamConstants.defaultTimeout
        )

        #expect(response.busEvent.payload == EventStreamConstants.serialHandlerOutputValue)
        #expect(result.value == EventStreamConstants.expectedSerialResult)
    }

    @Test
    func serialHandlerError() async throws {
        let eventBus = EventBus(defaultTimeout: EventStreamConstants.defaultTimeout)
        let result = LockIsolated<[Int]>([])
        eventBus.register(handlers: [
            EventStreamSerialHandler.handlerRegistration { value in
                try await sleepForSerialPayload(value)
                if value == EventStreamConstants.serialErrorValue {
                    throw EventStreamSerialHandlerError()
                }
                if value != EventStreamConstants.serialFlushValue {
                    result.withValue { $0.append(value) }
                }
                return EventStreamConstants.serialHandlerOutputValue
            },
        ])

        for int in EventStreamConstants.serialInputValues {
            await EventStreamSerialHandler.send(eventBus: eventBus, payload: int)
        }

        let response = try await EventStreamSerialHandler.sendAndWaitForResponse(
            eventBus: eventBus,
            payload: EventStreamConstants.serialFlushValue,
            timeout: EventStreamConstants.defaultTimeout
        )

        #expect(response.busEvent.payload == EventStreamConstants.serialHandlerOutputValue)
        #expect(result.value == EventStreamConstants.expectedSerialErrorResult)
    }

    @Test
    func sendAndWaitForMatchingResultSuccess() async throws {
        let eventBus = EventBus(defaultTimeout: EventStreamConstants.defaultTimeout)
        let testService = ColoredFoodTestService()
        eventBus.register(handlers: [
            EventStreamColorHandler.handlerRegistration {
                await testService.addColorToPayload(
                    $0,
                    outputEventType: EventStreamConstants.foodServiceEventType
                )
            },
        ])

        let result: EventStreamFoodEvent.TrackedEvent = try await eventBus.sendAndWaitForMatchingResult(
            EventStreamColorEvent.event(
                payload: TestPayloadWithColoredFood(eventType: EventStreamConstants.colorServiceEventType)
            ),
            resultType: EventStreamFoodEvent.eventType,
            matchingOptions: [.matchResponse(.direct)],
            timeout: EventStreamConstants.defaultTimeout
        )

        #expect(result.busEvent.eventType == EventStreamFoodEvent.eventType)
        #expect(ColoredFoodTestService.isColorValidForRecord(result.busEvent.payload.coloredFoodTestRecord))
    }

    @Test
    func sendAndWaitForMatchingResultTimeout() async throws {
        let eventBus = EventBus(defaultTimeout: EventStreamConstants.defaultTimeout)
        let testService = ColoredFoodTestService()
        eventBus.register(handlers: [
            EventStreamColorHandler.handlerRegistration {
                try await Task.sleep(for: EventStreamConstants.delayedHandlerSleep)
                return await testService.addColorToPayload(
                    $0,
                    outputEventType: EventStreamConstants.foodServiceEventType
                )
            },
        ])

        do {
            let result: EventStreamFoodEvent.TrackedEvent = try await eventBus.sendAndWaitForMatchingResult(
                EventStreamColorEvent.event(
                    payload: TestPayloadWithColoredFood(eventType: EventStreamConstants.colorServiceEventType)
                ),
                resultType: EventStreamFoodEvent.eventType,
                matchingOptions: [.matchResponse(.direct)],
                timeout: EventStreamConstants.tooShortTimeout
            )
            Issue.record("Expected timeout error, got result: \(result.busEvent.eventType)")
        } catch {
            #expect(error as? EventBusError == .timeoutError, "Got \(error)")
        }
    }

    @Test
    func sendAndWaitForMatchingResultFails() async throws {
        let eventBus = EventBus(defaultTimeout: EventStreamConstants.defaultTimeout)
        eventBus.register(handlers: [
            EventStreamColorHandler.handlerRegistration { _ in
                throw EventStreamColorServiceError()
            },
        ])

        do {
            let result: EventStreamFoodEvent.TrackedEvent = try await eventBus.sendAndWaitForMatchingResult(
                EventStreamColorEvent.event(
                    payload: TestPayloadWithColoredFood(eventType: EventStreamConstants.colorServiceEventType)
                ),
                resultType: EventStreamFoodEvent.eventType,
                matchingOptions: [.matchResponse(.direct)],
                timeout: EventStreamConstants.defaultTimeout
            )
            Issue.record("Expected EventStreamColorServiceError, got result: \(result.busEvent.eventType)")
        } catch {
            #expect(error is EventStreamColorServiceError, "Got \(error)")
        }
    }
}

private extension EventStreamTests {
    func registerColoredFoodHandlers(
        testService: ColoredFoodTestService,
        eventBus: EventBus
    ) {
        eventBus.register(handlers: [
            EventStreamColorHandler.handlerRegistration {
                await testService.addColorToPayload(
                    $0,
                    outputEventType: EventStreamConstants.foodServiceEventType
                )
            },
            EventStreamFoodHandler.handlerRegistration {
                await testService.addFoodToPayload(
                    $0,
                    outputEventType: EventStreamConstants.critiqueServiceEventType
                )
            },
            EventStreamCritiqueHandler.handlerRegistration {
                await testService.addCritiqueToPayload(
                    $0,
                    outputEventType: EventStreamConstants.completeServiceEventType
                )
            },
        ])
    }

    func assertColoredFoodTestData(_ testService: ColoredFoodTestService) async {
        let handlerIORecordTypeCount = await testService.handlerIORecordTypeCount
        #expect(handlerIORecordTypeCount == EventStreamConstants.expectedHandlerTypeCount)

        let colorHandlerResults = await testService.getHandlerIORecordsForService(
            EventStreamConstants.colorServiceEventType
        )
        #expect(colorHandlerResults.count == EventStreamConstants.maxIterations)
        for result in colorHandlerResults {
            #expect(result.input.isBlank)
            #expect(result.output.isCritiqueBlank)
            #expect(result.output.isFoodBlank)
            #expect(ColoredFoodTestService.isColorValidForRecord(result.output), "color invalid \(result.output.color)")
        }

        let foodHandlerResults = await testService.getHandlerIORecordsForService(
            EventStreamConstants.foodServiceEventType
        )
        #expect(foodHandlerResults.count == EventStreamConstants.maxIterations)
        for result in foodHandlerResults {
            #expect(result.input.isCritiqueBlank)
            #expect(result.output.isCritiqueBlank)
            #expect(result.input.isFoodBlank)
            #expect(
                ColoredFoodTestService.isFoodValidForRecord(result.output),
                "food invalid \(result.output.food1) or \(result.output.food2)"
            )
            #expect(result.input.color == result.output.color)
        }

        let critiqueHandlerResults = await testService.getHandlerIORecordsForService(
            EventStreamConstants.critiqueServiceEventType
        )
        #expect(critiqueHandlerResults.count == EventStreamConstants.maxIterations)
        for result in critiqueHandlerResults {
            #expect(result.input.isCritiqueBlank)
            #expect(!result.output.isCritiqueBlank)
            #expect(result.input.food1 == result.output.food1)
            #expect(result.input.food2 == result.output.food2)
            #expect(result.input.color == result.output.color)
        }
    }
}

private enum EventStreamConstants {
    static let maxIterations = 100
    static let expectedHandlerTypeCount = 3
    static let defaultTimeout: Duration = .milliseconds(300)
    static let tooShortTimeout: Duration = .microseconds(300)
    static let delayedHandlerSleep: Duration = .milliseconds(25)
    static let colorServiceEventType = "color"
    static let foodServiceEventType = "food"
    static let critiqueServiceEventType = "critique"
    static let completeServiceEventType = "complete"
    static let serialInputValues = [1, 2, 3, 4]
    static let expectedSerialResult = serialInputValues
    static let expectedSerialErrorResult = [1, 3, 4]
    static let serialFlushValue = 0
    static let serialErrorValue = 2
    static let serialHandlerOutputValue = 10
    static let serialPayloadSleepDurations: [Int: Duration] = [
        1: .milliseconds(8),
        2: .milliseconds(6),
        3: .milliseconds(4),
        4: .milliseconds(2),
    ]
}

private enum EventStreamColorEvent: SimpleBusEventType {
    typealias Payload = TestPayloadWithColoredFood
}

private enum EventStreamFoodEvent: SimpleBusEventType {
    typealias Payload = TestPayloadWithColoredFood
}

private enum EventStreamCritiqueEvent: SimpleBusEventType {
    typealias Payload = TestPayloadWithColoredFood
}

private enum EventStreamCompleteEvent: SimpleBusEventType {
    typealias Payload = TestPayloadWithColoredFood
}

private enum EventStreamColorHandler: LinkedEventPayloadHandler {
    typealias TriggerEvent = EventStreamColorEvent
    typealias ResponseEvent = EventStreamFoodEvent
}

private enum EventStreamFoodHandler: LinkedEventPayloadHandler {
    typealias TriggerEvent = EventStreamFoodEvent
    typealias ResponseEvent = EventStreamCritiqueEvent
}

private enum EventStreamCritiqueHandler: LinkedEventPayloadHandler {
    typealias TriggerEvent = EventStreamCritiqueEvent
    typealias ResponseEvent = EventStreamCompleteEvent
}

private enum EventStreamColorToCompleteLink: SimpleBusEventLink {
    typealias TriggerEvent = EventStreamColorEvent
    typealias ResponseEvent = EventStreamCompleteEvent
}

private enum EventStreamSerialHandler: RequestResponsePayloadHandler {
    typealias RequestPayload = Int
    typealias ResponsePayload = Int
    static let concurrencyType: EventBus.ConcurrencyType = .serial
}

private struct EventStreamSerialHandlerError: Error {}

private struct EventStreamColorServiceError: Error {}

private func sleepForSerialPayload(_ value: Int) async throws {
    if let sleepDuration = EventStreamConstants.serialPayloadSleepDurations[value] {
        try await Task.sleep(for: sleepDuration)
    }
}

// swiftlint:enable no_magic_numbers
