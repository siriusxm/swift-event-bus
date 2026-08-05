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
import Testing

@Suite("EventBusTests")
enum EventBusRequestResponseEventHandlerTests {
    @Suite("RequestResponsePayloadHandler tests")
    struct RequestResponsePayloadHandlerTests {
        @Test
        func requestResponseEventHandlerPayloadTest() async throws {
            let eventBus = EventBus(defaultTimeout: .milliseconds(300))
            enum SamMealHandler: RequestResponsePayloadHandler {
                // the request payload holds the name of the meal
                typealias RequestPayload = String
                // the response payload has a summary of what happened in the meal
                typealias ResponsePayload = (String, String)
            }

            #expect(SamMealHandler.requestID == ObjectIdentifier(SamMealHandler.RequestEvent.self))
            let breakfastString = "Breakfast!"
            let requestEvent = SamMealHandler.request(payload: breakfastString)
            #expect(requestEvent.eventType == ObjectIdentifier(SamMealHandler.RequestEvent.self))
            #expect(requestEvent.payload == breakfastString)

            let breakfastTrackedEvent = SamMealHandler.TrackedRequest(busEvent: requestEvent, eventBus: eventBus)
            #expect(breakfastTrackedEvent.busEvent.eventType == ObjectIdentifier(SamMealHandler.RequestEvent.self))
            #expect(breakfastTrackedEvent.busEvent.payload == breakfastString)

            let foodString = "you call this food?"
            #expect(SamMealHandler.responseID == ObjectIdentifier(SamMealHandler.ResponseEvent.self))
            let responseEvent = SamMealHandler.response(payload: (foodString, breakfastString))
            #expect(responseEvent.eventType == ObjectIdentifier(SamMealHandler.ResponseEvent.self))
            #expect(responseEvent.payload == (foodString, breakfastString))

            let responseTrackedEvent = SamMealHandler.TrackedResponse(busEvent: responseEvent, eventBus: eventBus)
            #expect(responseTrackedEvent.busEvent.eventType == ObjectIdentifier(SamMealHandler.ResponseEvent.self))
            #expect(responseTrackedEvent.busEvent.payload == (foodString, breakfastString))

            // In this simplified case, we're declaring the handler function as an independent closure.
            // Usually handler functions will be instance methods on a non-trivial object or actor
            let handler: SamMealHandler.HandlerType = { mealName in
                let food = ColoredFoodTestService.generateFood()
                return (food, mealName)
            }

            eventBus.register(
                handlers: [SamMealHandler.handlerRegistration(handler)]
            )

            let lunchString = "Lunch Time!"
            let result = try await SamMealHandler.sendAndWaitForResponse(eventBus: eventBus, payload: lunchString)
            #expect(result.busEvent.eventType == SamMealHandler.responseID)
            #expect(result.busEvent.payload.1 == lunchString)
            #expect(ColoredFoodTestService.isFoodValid(food: result.busEvent.payload.0))

            let dinnerString = "Dinner Time!"
            let explicitTimeoutParamResult = try await SamMealHandler.sendAndWaitForResponse(
                eventBus: eventBus,
                payload: dinnerString,
                timeout: .milliseconds(300)
            )
            #expect(explicitTimeoutParamResult.busEvent.payload.1 == dinnerString)

            guard let explicitTimeoutParamChainedResult = try await SamMealHandler.sendAndWaitForResponse(
                inputEvent: result,
                payload: dinnerString,
                timeout: .milliseconds(300)
            ) else {
                Issue.record("unexpected nil result on chained sendAndWait")
                return
            }
            #expect(explicitTimeoutParamChainedResult.busEvent.payload.1 == dinnerString)

            // this picks the triggering LunchTime event out of the sendAndWait result's history
            let historyLunchEvent: SamMealHandler.Request? = try? result.findFirstEvent(
                ofType: SamMealHandler.requestID
            )
            #expect(historyLunchEvent?.eventType == SamMealHandler.requestID)
            #expect(historyLunchEvent?.payload == lunchString)
        }

        @Test
        func requestResponseVoidPayloadHandlerTest() async throws {
            let eventBus = EventBus(defaultTimeout: .milliseconds(300))
            // in this test all the payloads are void
            // this happens when the services are very decoupled and the only pertinent information is that an event occured and was handled
            // more often there will be data exchanged by the processes or at least conveyed out to the system for troubleshooting
            enum SamMealHandler: RequestResponsePayloadHandler {
                typealias RequestPayload = Void
                typealias ResponsePayload = Void
            }

            #expect(SamMealHandler.requestID == ObjectIdentifier(SamMealHandler.RequestEvent.self))
            let requestEvent = SamMealHandler.request()
            #expect(requestEvent.eventType == ObjectIdentifier(SamMealHandler.RequestEvent.self))
            #expect(requestEvent.payload == ())

            let breakfastTrackedEvent = SamMealHandler.TrackedRequest(busEvent: requestEvent, eventBus: eventBus)
            #expect(breakfastTrackedEvent.busEvent.eventType == ObjectIdentifier(SamMealHandler.RequestEvent.self))
            #expect(breakfastTrackedEvent.busEvent.payload == ())

            #expect(SamMealHandler.responseID == ObjectIdentifier(SamMealHandler.ResponseEvent.self))
            let responseEvent = SamMealHandler.response()
            #expect(responseEvent.eventType == ObjectIdentifier(SamMealHandler.ResponseEvent.self))
            #expect(responseEvent.payload == ())

            let responseTrackedEvent = SamMealHandler.TrackedResponse(busEvent: responseEvent, eventBus: eventBus)
            #expect(responseTrackedEvent.busEvent.eventType == ObjectIdentifier(SamMealHandler.ResponseEvent.self))
            #expect(responseTrackedEvent.busEvent.payload == ())

            let didHandleMeal = LockIsolated(false)
            let samMealHandler: SamMealHandler.HandlerType = { _ in
                didHandleMeal.setValue(true)
            }

            eventBus.register(
                handlers: [
                    SamMealHandler.handlerRegistration(samMealHandler),
                ]
            )

            let result = try await SamMealHandler.sendAndWaitForResponse(eventBus: eventBus)
            #expect(result.busEvent.eventType == ObjectIdentifier(SamMealHandler.ResponseEvent.self))
            #expect(result.busEvent.payload == ())
            #expect(didHandleMeal.value)

            // this picks the request event out of the sendAndWait result's history
            guard let historyLunchEvent: SamMealHandler.Request = try? result.findFirstEvent(
                ofType: SamMealHandler.requestID
            ) else {
                Issue.record("unexpected nil result on findFirstEvent")
                return
            }
            #expect(historyLunchEvent.eventType == ObjectIdentifier(SamMealHandler.RequestEvent.self))
            #expect(historyLunchEvent.payload == ())
        }

        @Test
        func requestResponseVoidSendConveniencesTest() async {
            enum PayloadHandler: RequestResponsePayloadHandler {}

            enum TrackedHandler: RequestResponseTrackedBusEventHandler {}

            let eventBus = EventBus()
            let payloadRecorder = EventHistoryTestRecorder()
            let trackedRecorder = EventHistoryTestRecorder()

            let payloadHandler: PayloadHandler.HandlerType = { _ in
                await payloadRecorder.record([])
            }
            let trackedHandler: TrackedHandler.HandlerType = { inputEvent in
                await trackedRecorder.record(inputEvent.eventHistory)
                return nil
            }
            eventBus.register(handlers: [
                PayloadHandler.handlerRegistration(payloadHandler),
                TrackedHandler.handlerRegistration(trackedHandler),
            ])

            await PayloadHandler.send(eventBus: eventBus)
            _ = await payloadRecorder.nextHistory()

            let payloadInputEvent = PayloadHandler.TrackedRequest(
                busEvent: PayloadHandler.request(),
                eventBus: eventBus
            )
            await PayloadHandler.send(inputEvent: payloadInputEvent)
            _ = await payloadRecorder.nextHistory()

            await TrackedHandler.send(eventBus: eventBus)
            let trackedDirectSendHistory = await trackedRecorder.nextHistory()
            let lastHistoryEventType = trackedDirectSendHistory.last?.busEvent.eventType as? TrackedHandler.Request.EventType
            #expect(lastHistoryEventType == TrackedHandler.requestID)
            #expect(trackedDirectSendHistory.count == 1)

            let trackedInputEvent = TrackedHandler.TrackedRequest(
                busEvent: TrackedHandler.request(),
                eventBus: eventBus
            )
            await TrackedHandler.send(inputEvent: trackedInputEvent)
            let trackedChainedSendHistory = await trackedRecorder.nextHistory()
            let chainedHistoryEventType = trackedChainedSendHistory.last?.busEvent.eventType as? TrackedHandler.Request.EventType
            #expect(chainedHistoryEventType == TrackedHandler.requestID)
            #expect(trackedChainedSendHistory.count == 2)
        }

        @Test
        func requestResponseHandlersReturnNilWithoutEventBusCallback() async throws {
            enum InputEvent: SimpleBusEventType {}

            enum PayloadHandler: RequestResponsePayloadHandler {}

            enum TrackedHandler: RequestResponseTrackedBusEventHandler {}

            let inputEvent = InputEvent.TrackedEvent(
                eventHistory: [],
                busEvent: InputEvent.event(),
                eventBus: nil
            )
            let payloadResult: PayloadHandler.TrackedResponse? = try await PayloadHandler.sendAndWaitForResponse(
                inputEvent: inputEvent
            )
            #expect(payloadResult == nil)

            let trackedResult: TrackedHandler.TrackedResponse? = try await TrackedHandler.sendAndWaitForResponse(
                inputEvent: inputEvent
            )
            #expect(trackedResult == nil)
        }
    }
}
