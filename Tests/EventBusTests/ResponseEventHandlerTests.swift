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
import ConcurrencyExtras
import EventBusTestSupport
import Foundation
import Testing

@Suite("EventBusTests")
enum EventBusResponseEventHandlerTests {
    @Suite("SimpleBusEvent basic tests")
    struct SimpleBusEventBasicTests {
        @Test
        func simpleBusEventTypeVoidPayloadTest() async throws {
            enum LunchTime: SimpleBusEventType {
                typealias Payload = Void
            }

            #expect(LunchTime.eventType == ObjectIdentifier(LunchTime.self))
            let lunchTimeEvent = LunchTime.event()
            #expect(lunchTimeEvent.eventType == ObjectIdentifier(LunchTime.self))
            #expect(lunchTimeEvent.payload == ())

            let eventBus = EventBus(defaultTimeout: .milliseconds(300))
            let lunchTimeTrackedEvent = LunchTime.TrackedEvent(busEvent: lunchTimeEvent, eventBus: eventBus)
            #expect(lunchTimeTrackedEvent.busEvent.eventType == ObjectIdentifier(LunchTime.self))
            #expect(lunchTimeTrackedEvent.busEvent.payload == ())

            enum SamLunchHandler: ResponsePayloadHandler {
                typealias TriggerEvent = LunchTime
                // Having a void payload in a ResponseHandler is not a best practice, except for corner cases.
                // Handlers should generally return some kind of result for testing/troubleshooting.
                // This is void here so the void ResponseHandler extensions get tested.
                typealias Payload = Void
            }

            let responseEvent = SamLunchHandler.response()
            #expect(responseEvent.eventType == SamLunchHandler.responseID)
            #expect(responseEvent.payload == ())

            // In this simplified case, we're declaring the handler function as an independent closure.
            // Usually handler functions will be instance methods on a non-trivial object or actor
            let lunches = LockIsolated<[String]>([])
            let handler: SamLunchHandler.HandlerType = { _ in
                lunches.withValue { $0.append(ColoredFoodTestService.generateFood()) }
            }

            eventBus.register(
                handlers: [SamLunchHandler.handlerRegistration(handler)]
            )

            func checkResult(_ result: SamLunchHandler.TrackedResponse?) {
                guard let result else {
                    Issue.record("unexpected nil result on sendAndWait")
                    return
                }
                #expect(result.busEvent.eventType == ObjectIdentifier(SamLunchHandler.self))
                #expect(result.busEvent.payload == ())

                // this picks the triggering LunchTime event out of the sendAndWait result's history
                guard let historyLunchEvent: LunchTime.Event = try? result.findFirstEvent(ofType: LunchTime.eventType) else {
                    Issue.record("unexpected nil result on findFirstEvent")
                    return
                }
                #expect(historyLunchEvent.eventType == ObjectIdentifier(LunchTime.self))
                #expect(historyLunchEvent.payload == ())
            }

            let chainResult = try await SamLunchHandler.sendAndWaitForResponse(eventBus: eventBus)
            checkResult(chainResult)
            try await checkResult(SamLunchHandler.sendAndWaitForResponse(inputEvent: chainResult))
            try await checkResult(SamLunchHandler.sendAndWaitForResponse(inputEvent: chainResult, timeout: .milliseconds(300)))

            // normally you wouldn't need to use a SimpleBusEventLink when you already have a ResponseTrackedBusEventHandler
            // but creating one here to get test coverage for SimpleBusEventLink
            enum SamLunchLink: SimpleBusEventLink {
                typealias TriggerEvent = LunchTime
                typealias ResponseEvent = SamLunchHandler
            }

            try await checkResult(SamLunchLink.sendAndWaitForResponse(eventBus: eventBus))
            #expect(lunches.value.count == 4)
            #expect(lunches.value.allSatisfy { ColoredFoodTestService.isFoodValid(food: $0) })
        }

        @Test
        func simpleBusEventTypeStringPayloadTest() async throws {
            enum LunchTime: SimpleBusEventType {
                typealias Payload = String
            }

            #expect(LunchTime.eventType == ObjectIdentifier(LunchTime.self))
            let lunchString = "Lunch Time!"
            let lunchTimeEvent = LunchTime.event(payload: lunchString)
            #expect(lunchTimeEvent.eventType == ObjectIdentifier(LunchTime.self))
            #expect(lunchTimeEvent.payload == lunchString)

            let eventBus = EventBus(defaultTimeout: .milliseconds(300))
            let lunchTimeTrackedevent = LunchTime.TrackedEvent(busEvent: lunchTimeEvent, eventBus: eventBus)
            #expect(lunchTimeTrackedevent.busEvent.eventType == ObjectIdentifier(LunchTime.self))
            #expect(lunchTimeTrackedevent.busEvent.payload == lunchString)

            enum SamLunchHandler: ResponsePayloadHandler {
                typealias TriggerEvent = LunchTime
                typealias ResponsePayload = String
            }

            // In this simplified case, we're declaring the handler function as an independent closure.
            // Usually handler functions will be instance methods on a non-trivial object or actor
            let servedLunches = LockIsolated<[(occasion: String, food: String)]>([])
            let handler: SamLunchHandler.HandlerType = { occasion in
                let lunch = ColoredFoodTestService.generateFood()
                servedLunches.withValue { $0.append((occasion, lunch)) }
                return lunch
            }

            eventBus.register(
                handlers: [SamLunchHandler.handlerRegistration(handler)]
            )

            enum SamLunchLink: SimpleBusEventLink {
                typealias TriggerEvent = LunchTime
                typealias ResponseEvent = SamLunchHandler
            }

            let secondLunchString = "Second Lunch Time!"
            let result = try await SamLunchLink.sendAndWaitForResponse(eventBus: eventBus, payload: secondLunchString)
            #expect(result.busEvent.eventType == ObjectIdentifier(SamLunchHandler.self))
            #expect(ColoredFoodTestService.isFoodValid(food: result.busEvent.payload))
            #expect(servedLunches.value.map(\.occasion) == [secondLunchString])
            #expect(servedLunches.value.map(\.food) == [result.busEvent.payload])

            // this picks the triggering LunchTime event out of the sendAndWait result's history
            let historyLunchEvent: LunchTime.Event? = try? result.findFirstEvent(ofType: LunchTime.eventType)
            #expect(historyLunchEvent?.eventType == ObjectIdentifier(LunchTime.self))
            #expect(historyLunchEvent?.payload == secondLunchString)
        }

        @Test
        func simpleBusEventTypeTrackedBusEventTest() async throws {
            // TrackedBusEvent handler tests need at least one non-void event, so combining void and non-void tests here
            // The outer event handler will be triggered by a void event and return a void response
            enum LunchTime: SimpleBusEventType {
                typealias Payload = Void
            }

            enum SamLunchHandler: ResponseTrackedBusEventHandler {
                typealias TriggerEvent = LunchTime
                // Having a void payload in a ResponseHandler is not a best practice, except for corner cases.
                // Handlers should generally return some kind of result for testing/troubleshooting.
                // This is void here so the void ResponseHandler extensions get tested.
                typealias ResponsePayload = Void
            }

            let servedLunches = LockIsolated<[(customer: String, food: String)]>([])
            let lunchHandler: SamLunchHandler.HandlerType = { inputEvent in
                guard let lunchOrder = try await DoorDashHandler.sendAndWaitForResponse(
                    inputEvent: inputEvent,
                    payload: "Sam"
                ) else {
                    throw EventBusError.unexpectedError("unexpected nil response in test")
                }
                servedLunches.withValue {
                    $0.append((lunchOrder.busEvent.payload.customerName, lunchOrder.busEvent.payload.food))
                }
                return await inputEvent.appendEvent(SamLunchHandler.response())
            }

            // TrackedBusEventHandlers exist so the handler can call back into the EventBus,
            // so this creates an inner event handler the outer hander can call
            // this uses a populated response payload which is the normal best practice
            enum FoodOrder: SimpleBusEventType {
                typealias Payload = String
            }
            struct DoorDashOrderResponse {
                let customerName: String
                let food: String
            }
            enum DoorDashHandler: ResponsePayloadHandler {
                typealias TriggerEvent = FoodOrder
                typealias ResponsePayload = DoorDashOrderResponse
            }

            let foodOrders = LockIsolated<[(customer: String, food: String)]>([])
            let doorDashHandler: DoorDashHandler.HandlerType = { customerName in
                let food = ColoredFoodTestService.generateFood()
                foodOrders.withValue { $0.append((customerName, food)) }
                return DoorDashOrderResponse(customerName: customerName, food: food)
            }

            let eventBus = EventBus(defaultTimeout: .milliseconds(300))
            eventBus.register(
                handlers: [
                    SamLunchHandler.handlerRegistration(lunchHandler),
                    DoorDashHandler.handlerRegistration(doorDashHandler),
                ]
            )

            func checkSamLunchResult(result: SamLunchHandler.TrackedResponse?) {
                guard let result else {
                    Issue.record("unexpected nil result on sendAndWait")
                    return
                }
                #expect(result.busEvent.eventType == ObjectIdentifier(SamLunchHandler.self))
                #expect(result.busEvent.payload == ())

                // this picks the triggering LunchTime event out of the sendAndWait result's history
                guard let historyLunchEvent: LunchTime.Event = try? result.findFirstEvent(ofType: LunchTime.eventType) else {
                    Issue.record("unexpected nil result on findFirstEvent")
                    return
                }
                #expect(historyLunchEvent.eventType == ObjectIdentifier(LunchTime.self))
                #expect(historyLunchEvent.payload == ())
            }

            let chainResult = try await SamLunchHandler.sendAndWaitForResponse(eventBus: eventBus)
            checkSamLunchResult(result: chainResult)
            try await checkSamLunchResult(result: SamLunchHandler.sendAndWaitForResponse(inputEvent: chainResult))
            try await checkSamLunchResult(
                result: SamLunchHandler.sendAndWaitForResponse(inputEvent: chainResult, timeout: .milliseconds(300))
            )

            // normally you wouldn't need to use a SimpleBusEventLink when you already have a ResponseTrackedBusEventHandler
            // but creating one here to get test coverage for SimpleBusEventLink
            enum SamLunchLink: SimpleBusEventLink {
                typealias TriggerEvent = LunchTime
                typealias ResponseEvent = SamLunchHandler
            }

            try await checkSamLunchResult(result: SamLunchLink.sendAndWaitForResponse(eventBus: eventBus))
            #expect(foodOrders.value.map(\.customer) == ["Sam", "Sam", "Sam", "Sam"])
            #expect(foodOrders.value.map(\.food) == servedLunches.value.map(\.food))
            #expect(servedLunches.value.map(\.customer) == ["Sam", "Sam", "Sam", "Sam"])
        }

        @Test
        func simpleBusEventSendTest() async {
            // this test makes sure all the send function variations get their events into the bus properly
            // it leaves out handler registration and verifying that the events are handled, which is covered elsehwere
            let mockLogger = MockEventSavingBusLogger()
            let eventBus = EventBus(eventBusLogger: mockLogger)

            // Void payload events call the non-void send internally, so this test covers both
            enum LunchTime: SimpleBusEventType {
                typealias Payload = Void
            }

            // send version that takes an EventBus directly
            await LunchTime.send(eventBus: eventBus)
            guard let sentTrackedEvent1 = mockLogger.latestEvents().last as? LunchTime.TrackedEvent else {
                Issue.record("unexpected nil event from MockEventSavingBusLogger")
                return
            }
            #expect(sentTrackedEvent1.busEvent.eventType == LunchTime.eventType)
            mockLogger.clearEvents()

            // send version that takes a TrackedBusEvent to chain to the new event
            await LunchTime.send(inputEvent: sentTrackedEvent1)
            guard let sentTrackedEvent2 = mockLogger.latestEvents().last as? LunchTime.TrackedEvent else {
                Issue.record("unexpected nil event from MockEventSavingBusLogger")
                return
            }
            #expect(sentTrackedEvent2.busEvent.eventType == LunchTime.eventType)
            #expect(sentTrackedEvent2.eventHistory.count == 2)
        }
    }
}

extension EventBusResponseEventHandlerTests {
    @Suite("ResponseEventHandler tests")
    struct ResponseEventHandlerTests {
        @Test
        func responseEventHandlerPopulatedPayloadTest() async throws {
            // in this test, all payloads are populated
            enum LunchTime: SimpleBusEventType {
                typealias Payload = Date
            }

            struct PersonEatingLunchPayload: Sendable {
                let person: String
                let food: String
                let time: Date
            }

            // This demonstrates a handler object that is an instance of a struct with a function that references a data member
            struct PersonAndTheirFoodHandler {
                let person: String

                @Sendable func personEatingLunchHandler(
                    date: PersonEatingLunch.TriggerEvent.Payload
                ) async throws -> PersonEatingLunch.ResponsePayload {
                    let lunch = ColoredFoodTestService.generateFood()
                    return PersonEatingLunchPayload(
                        person: person,
                        food: lunch,
                        time: date
                    )
                }
            }

            enum PersonEatingLunch: ResponsePayloadHandler {
                typealias TriggerEvent = LunchTime
                typealias ResponsePayload = PersonEatingLunchPayload
            }

            let testDate = try #require(ISO8601DateFormatter().date(from: "1999-12-31T00:00:00Z"))
            #expect(PersonEatingLunch.TriggerEvent.eventType == ObjectIdentifier(LunchTime.self))
            let lunchTimeEvent = PersonEatingLunch.TriggerEvent.event(payload: testDate)
            #expect(lunchTimeEvent.eventType == ObjectIdentifier(LunchTime.self))
            #expect(lunchTimeEvent.payload == testDate)

            let eventBus = EventBus(defaultTimeout: .milliseconds(300))
            let lunchTimeTrackedEvent = PersonEatingLunch.TriggerEvent.TrackedEvent(busEvent: lunchTimeEvent, eventBus: eventBus)
            #expect(lunchTimeTrackedEvent.busEvent.eventType == ObjectIdentifier(LunchTime.self))
            #expect(PersonEatingLunch.eventID == ObjectIdentifier(LunchTime.self))
            #expect(lunchTimeTrackedEvent.busEvent.payload == testDate)

            let samFoodHandler = PersonAndTheirFoodHandler(person: "Sam")
            eventBus.register(
                handlers: [
                    PersonEatingLunch.handlerRegistration(samFoodHandler.personEatingLunchHandler),
                ]
            )

            let result = try await PersonEatingLunch.sendAndWaitForResponse(eventBus: eventBus, payload: testDate)
            #expect(result.busEvent.eventType == ObjectIdentifier(PersonEatingLunch.self))
            #expect(result.busEvent.payload.person == samFoodHandler.person)
            #expect(ColoredFoodTestService.isFoodValid(food: result.busEvent.payload.food))
            #expect(result.busEvent.payload.time == testDate)
        }

        @Test
        func responseHandlersReturnNilWithoutEventBusCallback() async throws {
            enum LunchTime: SimpleBusEventType {}

            enum PayloadLunchHandler: ResponsePayloadHandler {
                typealias TriggerEvent = LunchTime
            }

            enum TrackedLunchHandler: ResponseTrackedBusEventHandler {
                typealias TriggerEvent = LunchTime
            }

            let inputEvent = LunchTime.TrackedEvent(
                eventHistory: [],
                busEvent: LunchTime.event(),
                eventBus: nil
            )
            let payloadResult: PayloadLunchHandler.TrackedResponse? = try await PayloadLunchHandler.sendAndWaitForResponse(
                inputEvent: inputEvent
            )
            #expect(payloadResult == nil)

            let trackedResult: TrackedLunchHandler.TrackedResponse? = try await TrackedLunchHandler.sendAndWaitForResponse(
                inputEvent: inputEvent
            )
            #expect(trackedResult == nil)
        }
    }
}
