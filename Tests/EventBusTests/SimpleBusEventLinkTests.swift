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

@Suite("SimpleBusEventLink tests")
struct SimpleBusEventLinkTests {
    @Suite("LinkedEventPayloadHandler tests")
    struct LinkedEventPayloadHandlerTests {
        @Test
        func linkedEventPayloadHandlerVoidPayloadTest() async throws {
            enum LunchTime: SimpleBusEventType {
                typealias Payload = Void
            }

            enum LunchResponse: SimpleBusEventType {
                typealias Payload = Void
            }

            enum SamLunchHandler: LinkedEventPayloadHandler {
                typealias TriggerEvent = LunchTime
                typealias ResponseEvent = LunchResponse
            }

            let lunches = LockIsolated<[String]>([])
            let handler: SamLunchHandler.HandlerType = { _ in
                lunches.withValue { $0.append(ColoredFoodTestService.generateFood()) }
            }

            let eventBus = EventBus(defaultTimeout: .milliseconds(300))
            eventBus.register(
                handlers: [SamLunchHandler.handlerRegistration(handler)]
            )

            let result = try await SamLunchHandler.sendAndWaitForResponse(eventBus: eventBus)
            #expect(result.busEvent.eventType == ObjectIdentifier(LunchResponse.self))
            #expect(result.busEvent.payload == ())
            #expect(lunches.value.count == 1)
            #expect(lunches.value.allSatisfy { ColoredFoodTestService.isFoodValid(food: $0) })

            guard let historyLunchEvent: LunchTime.Event = try? result.findFirstEvent(ofType: LunchTime.eventType) else {
                Issue.record("unexpected nil result on findFirstEvent")
                return
            }
            #expect(historyLunchEvent.eventType == ObjectIdentifier(LunchTime.self))
            #expect(historyLunchEvent.payload == ())
        }

        @Test
        func linkedEventPayloadHandlerPopulatedPayloadTest() async throws {
            enum LunchTime: SimpleBusEventType {
                typealias Payload = String
            }

            enum LunchResponse: SimpleBusEventType {
                typealias Payload = String
            }

            enum SamLunchHandler: LinkedEventPayloadHandler {
                typealias TriggerEvent = LunchTime
                typealias ResponseEvent = LunchResponse
            }

            let servedLunches = LockIsolated<[(customer: String, food: String)]>([])
            let handler: SamLunchHandler.HandlerType = { customerName in
                let lunch = ColoredFoodTestService.generateFood()
                servedLunches.withValue { $0.append((customerName, lunch)) }
                return lunch
            }

            let eventBus = EventBus(defaultTimeout: .milliseconds(300))
            eventBus.register(
                handlers: [SamLunchHandler.handlerRegistration(handler)]
            )

            let customerName = "Sam"
            let result = try await SamLunchHandler.sendAndWaitForResponse(
                eventBus: eventBus,
                payload: customerName
            )
            #expect(result.busEvent.eventType == ObjectIdentifier(LunchResponse.self))
            #expect(ColoredFoodTestService.isFoodValid(food: result.busEvent.payload))

            let explicitTimeoutResult = try await SamLunchHandler.sendAndWaitForResponse(
                eventBus: eventBus,
                payload: customerName,
                timeout: .milliseconds(300)
            )
            #expect(explicitTimeoutResult.busEvent.eventType == ObjectIdentifier(LunchResponse.self))
            #expect(ColoredFoodTestService.isFoodValid(food: explicitTimeoutResult.busEvent.payload))
            #expect(servedLunches.value.map(\.customer) == [customerName, customerName])
            #expect(servedLunches.value.map(\.food) == [
                result.busEvent.payload,
                explicitTimeoutResult.busEvent.payload,
            ])

            let historyLunchEvent: LunchTime.Event? = try? result.findFirstEvent(ofType: LunchTime.eventType)
            #expect(historyLunchEvent?.eventType == ObjectIdentifier(LunchTime.self))
            #expect(historyLunchEvent?.payload == customerName)
        }

        @Test
        func linkedEventPayloadHandlerChainedTest() async throws {
            enum LunchTime: SimpleBusEventType {
                typealias Payload = Void
            }

            enum LunchResponse: SimpleBusEventType {
                typealias Payload = String
            }

            enum SamLunchHandler: LinkedEventPayloadHandler {
                typealias TriggerEvent = LunchTime
                typealias ResponseEvent = LunchResponse
            }

            let lunches = LockIsolated<[String]>([])
            let handler: SamLunchHandler.HandlerType = { _ in
                let lunch = ColoredFoodTestService.generateFood()
                lunches.withValue { $0.append(lunch) }
                return lunch
            }

            let eventBus = EventBus(defaultTimeout: .milliseconds(300))
            eventBus.register(
                handlers: [SamLunchHandler.handlerRegistration(handler)]
            )

            let chainResult = try await SamLunchHandler.sendAndWaitForResponse(eventBus: eventBus)

            guard let secondResult = try await SamLunchHandler.sendAndWaitForResponse(inputEvent: chainResult) else {
                Issue.record("unexpected nil result on chained sendAndWait")
                return
            }

            #expect(secondResult.busEvent.eventType == ObjectIdentifier(LunchResponse.self))
            #expect(ColoredFoodTestService.isFoodValid(food: secondResult.busEvent.payload))
            #expect(secondResult.eventHistory.count == 4)

            guard let explicitTimeoutParamResult = try await SamLunchHandler.sendAndWaitForResponse(
                inputEvent: chainResult,
                timeout: .milliseconds(300)
            ) else {
                Issue.record("unexpected nil result on chained sendAndWait")
                return
            }
            #expect(explicitTimeoutParamResult.busEvent.eventType == ObjectIdentifier(LunchResponse.self))
            #expect(ColoredFoodTestService.isFoodValid(food: explicitTimeoutParamResult.busEvent.payload))
            #expect(explicitTimeoutParamResult.eventHistory.count == 4)
            #expect(lunches.value == [
                chainResult.busEvent.payload,
                secondResult.busEvent.payload,
                explicitTimeoutParamResult.busEvent.payload,
            ])
        }

        @Test
        func linkedEventReturnsNilWithoutEventBusCallback() async throws {
            enum LunchTime: SimpleBusEventType {}

            enum LunchResponse: SimpleBusEventType {}

            enum SamLunchHandler: LinkedEventPayloadHandler {
                typealias TriggerEvent = LunchTime
                typealias ResponseEvent = LunchResponse
            }

            let inputEvent = LunchTime.TrackedEvent(
                eventHistory: [],
                busEvent: LunchTime.event(),
                eventBus: nil
            )
            let result: LunchResponse.TrackedEvent? = try await SamLunchHandler.sendAndWaitForResponse(inputEvent: inputEvent)
            #expect(result == nil)
        }
    }

    @Suite("LinkedTrackedBusEventHandler tests")
    struct LinkedTrackedBusEventHandlerTests {
        @Test
        func linkedTrackedBusEventHandlerVoidPayloadTest() async throws {
            enum LunchTime: SimpleBusEventType {
                typealias Payload = Void
            }

            enum LunchResponse: SimpleBusEventType {
                typealias Payload = Void
            }

            enum SamLunchHandler: LinkedTrackedBusEventHandler {
                typealias TriggerEvent = LunchTime
                typealias ResponseEvent = LunchResponse
            }

            let lunches = LockIsolated<[String]>([])
            let handler: SamLunchHandler.HandlerType = { inputEvent in
                lunches.withValue { $0.append(ColoredFoodTestService.generateFood()) }
                return await inputEvent.appendEvent(LunchResponse.event())
            }

            let eventBus = EventBus(defaultTimeout: .milliseconds(300))
            eventBus.register(
                handlers: [SamLunchHandler.handlerRegistration(handler)]
            )

            let result = try await SamLunchHandler.sendAndWaitForResponse(eventBus: eventBus)
            #expect(result.busEvent.eventType == ObjectIdentifier(LunchResponse.self))
            #expect(result.busEvent.payload == ())

            guard let historyLunchEvent: LunchTime.Event = try? result.findFirstEvent(ofType: LunchTime.eventType) else {
                Issue.record("unexpected nil result on findFirstEvent")
                return
            }
            #expect(historyLunchEvent.eventType == ObjectIdentifier(LunchTime.self))
            #expect(historyLunchEvent.payload == ())

            // this is to get coverage for the sendAndWait that takes a result
            guard let result2 = try await SamLunchHandler.sendAndWaitForResponse(inputEvent: result) else {
                Issue.record("unexpected nil result on sendAndWait")
                return
            }
            #expect(result2.busEvent.eventType == ObjectIdentifier(LunchResponse.self))
            #expect(result2.busEvent.payload == ())
            #expect(lunches.value.count == 2)
            #expect(lunches.value.allSatisfy { ColoredFoodTestService.isFoodValid(food: $0) })
        }

        @Test
        func linkedTrackedBusEventHandlerWithNestedCallTest() async throws {
            enum LunchTime: SimpleBusEventType {
                typealias Payload = Void
            }

            enum LunchResponse: SimpleBusEventType {
                typealias Payload = String
            }

            enum SamLunchHandler: LinkedTrackedBusEventHandler {
                typealias TriggerEvent = LunchTime
                typealias ResponseEvent = LunchResponse
            }

            enum FoodOrder: SimpleBusEventType {
                typealias Payload = String
            }

            enum OrderResponse: SimpleBusEventType {
                typealias Payload = String
            }

            enum DoorDashHandler: LinkedEventPayloadHandler {
                typealias TriggerEvent = FoodOrder
                typealias ResponseEvent = OrderResponse
            }

            let servedLunches = LockIsolated<[String]>([])
            let lunchHandler: SamLunchHandler.HandlerType = { inputEvent in
                guard let lunchOrderResponse = try await DoorDashHandler.sendAndWaitForResponse(
                    inputEvent: inputEvent,
                    payload: "Sam"
                ) else {
                    throw EventBusError.unexpectedError("unexpected nil response in test")
                }
                let food = lunchOrderResponse.busEvent.payload
                servedLunches.withValue { $0.append(food) }
                return await lunchOrderResponse.appendEvent(LunchResponse.event(payload: food))
            }

            let foodOrders = LockIsolated<[(customer: String, food: String)]>([])
            let doorDashHandler: DoorDashHandler.HandlerType = { customerName in
                let food = ColoredFoodTestService.generateFood()
                foodOrders.withValue { $0.append((customerName, food)) }
                return food
            }

            let eventBus = EventBus(defaultTimeout: .milliseconds(300))
            eventBus.register(
                handlers: [
                    SamLunchHandler.handlerRegistration(lunchHandler),
                    DoorDashHandler.handlerRegistration(doorDashHandler),
                ]
            )

            let result = try await SamLunchHandler.sendAndWaitForResponse(eventBus: eventBus)
            #expect(result.busEvent.eventType == ObjectIdentifier(LunchResponse.self))
            #expect(ColoredFoodTestService.isFoodValid(food: result.busEvent.payload))
            #expect(foodOrders.value.map(\.customer) == ["Sam"])
            #expect(foodOrders.value.map(\.food) == [result.busEvent.payload])
            #expect(servedLunches.value == [result.busEvent.payload])

            let historyLunchEvent: LunchTime.Event? = try? result.findFirstEvent(ofType: LunchTime.eventType)
            #expect(historyLunchEvent?.eventType == ObjectIdentifier(LunchTime.self))

            let historyOrderEvent: FoodOrder.Event? = try? result.findFirstEvent(ofType: FoodOrder.eventType)
            #expect(historyOrderEvent?.eventType == ObjectIdentifier(FoodOrder.self))
            #expect(historyOrderEvent?.payload == "Sam")

            let historyOrderResponse: OrderResponse.Event? = try? result.findFirstEvent(ofType: OrderResponse.eventType)
            #expect(historyOrderResponse?.eventType == ObjectIdentifier(OrderResponse.self))
            #expect(ColoredFoodTestService.isFoodValid(food: historyOrderResponse?.payload))
        }
    }
}
