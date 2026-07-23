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
import Testing

extension EventBusRequestResponseEventHandlerTests {
    @Suite("RequestResponseTrackedBusEventHandler tests")
    struct RequestResponseTrackedBusEventHndTests {
        @Test
        func requestResponseEventHandlerTrackedBusEventTest() async throws {
            let eventBus = EventBus(defaultTimeout: .milliseconds(300))
            typealias FoodResultPayload = (String, String)
            enum SamMealHandler: RequestResponseTrackedBusEventHandler {
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

            let foodString = "green eggs and ham"
            #expect(SamMealHandler.responseID == ObjectIdentifier(SamMealHandler.ResponseEvent.self))
            let responseEvent = SamMealHandler.response(payload: (foodString, breakfastString))
            #expect(responseEvent.eventType == ObjectIdentifier(SamMealHandler.ResponseEvent.self))
            #expect(responseEvent.payload == (foodString, breakfastString))

            let responseTrackedEvent = SamMealHandler.TrackedResponse(busEvent: responseEvent, eventBus: eventBus)
            #expect(responseTrackedEvent.busEvent.eventType == ObjectIdentifier(SamMealHandler.ResponseEvent.self))
            #expect(responseTrackedEvent.busEvent.payload == (foodString, breakfastString))

            let samMealHandler: SamMealHandler.HandlerType = { inputEvent in
                guard let foodResultEvent = try await MealMakingHandler.sendAndWaitForResponse(inputEvent: inputEvent) else {
                    return nil
                }
                let samMealResult = (foodResultEvent.busEvent.payload, inputEvent.busEvent.payload)
                logger.debug("🍽️ Sam had \(samMealResult.0) for \(samMealResult.1)", tag: "eventBus")
                guard let momInformingResult = try await MomInformingHandler.sendAndWaitForResponse(
                    inputEvent: foodResultEvent, payload: samMealResult
                ) else {
                    return nil
                }
                return await momInformingResult.appendEvent(SamMealHandler.response(payload: samMealResult))
            }

            // To fully test a TrackedBusEvent handler, it needs to call out to another handler
            // we're using two handlers here to cover PayloadHandler and TrackedBusEventHandler internals
            enum MomInformingHandler: RequestResponsePayloadHandler {
                // the request payload holds the result of sam's meal
                typealias RequestPayload = FoodResultPayload
                // the response payload has a summary of what happened in the meal
                typealias ResponsePayload = Void
            }

            // A payload handler that returns a void payload can be very simple, doesn't need a return statement
            let momInformingClosure: MomInformingHandler.HandlerType = { foodResult in
                logger.debug("🍽️ Thank God Sam is eating. He had \(foodResult.0) for \(foodResult.1)", tag: "eventBus")
            }

            // note it isn't best practice to use a TrackedBusEvent handler when a simpler PayloadHandler works
            // but to get more test coverage of the send function variations we're using one here
            enum MealMakingHandler: RequestResponseTrackedBusEventHandler {
                // the request payload holds the name of the meal
                typealias RequestPayload = Void
                // the response payload has a summary of what happened in the meal
                typealias ResponsePayload = String
            }

            // this function would be a simple one-liner if it was a payload handler
            // note this is a minimal TrackedBusEventHandler that needs to respond with a TrackedBusEvent chained to the inputEvent
            let mealMakingHandlerClosure: MealMakingHandler.HandlerType = { inputEvent in
                let food = ColoredFoodTestService.generateFood()
                return await inputEvent.appendEvent(MealMakingHandler.response(payload: food))
            }

            eventBus.register(
                handlers: [
                    SamMealHandler.handlerRegistration(samMealHandler),
                    MealMakingHandler.handlerRegistration(mealMakingHandlerClosure),
                    MomInformingHandler.handlerRegistration(momInformingClosure),
                ]
            )

            let lunchString = "Lunch Time!"
            let result = try await SamMealHandler.sendAndWaitForResponse(eventBus: eventBus, payload: lunchString)
            #expect(result.busEvent.eventType == ObjectIdentifier(SamMealHandler.ResponseEvent.self))
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

            // this picks the request event out of the sendAndWait result's history
            let historyLunchEvent: SamMealHandler.Request? = try? result.findFirstEvent(
                ofType: SamMealHandler.requestID
            )
            #expect(historyLunchEvent?.eventType == ObjectIdentifier(SamMealHandler.RequestEvent.self))

            // this picks the internal MealMaking result event out of the sendAndWait result's history
            guard let historyMealMakingEvent: MealMakingHandler.Response = try? result.findFirstEvent(
                ofType: MealMakingHandler.responseID
            ) else {
                Issue.record("unexpected nil result on findFirstEvent")
                return
            }
            #expect(historyMealMakingEvent.eventType == ObjectIdentifier(MealMakingHandler.ResponseEvent.self))
            #expect(ColoredFoodTestService.isFoodValid(food: historyMealMakingEvent.payload))

            // this picks the internal MomInforming request event out of the sendAndWait result's history
            guard let historyMomInformingEvent: MomInformingHandler.Request = try? result.findFirstEvent(
                ofType: MomInformingHandler.requestID
            ) else {
                Issue.record("unexpected nil result on findFirstEvent")
                return
            }
            #expect(historyMomInformingEvent.eventType == ObjectIdentifier(MomInformingHandler.RequestEvent.self))
            #expect(historyMomInformingEvent.payload == result.busEvent.payload)
        }

        @Test
        func requestResponseVoidTrackedBusEventHandlerTest() async throws {
            let eventBus = EventBus(defaultTimeout: .milliseconds(300))
            enum SamMealHandler: RequestResponseTrackedBusEventHandler {
                // the request payload holds the name of the meal
                typealias RequestPayload = Void
                // the response payload has a summary of what happened in the meal
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

            let samMealHandler: SamMealHandler.HandlerType = { inputEvent in
                guard let foodResultEvent = try await MealMakingHandler.sendAndWaitForResponse(inputEvent: inputEvent) else {
                    return nil
                }
                logger.debug("🍽️ Sam had some kind of food at some meal", tag: "eventBus")
                guard let momInformingResult = try await MomInformingHandler.sendAndWaitForResponse(inputEvent: foodResultEvent) else {
                    return nil
                }
                return await momInformingResult.appendEvent(SamMealHandler.response())
            }

            // To fully test a TrackedBusEvent handler, it needs to call out to another handler
            // we're using two handlers here to cover PayloadHandler and TrackedBusEventHandler internals
            enum MomInformingHandler: RequestResponsePayloadHandler {
                // the request payload holds the result of sam's meal
                typealias RequestPayload = Void
                // the response payload has a summary of what happened in the meal
                typealias ResponsePayload = Void
            }

            // A payload handler that returns a void payload can be very simple, doesn't need a return statement
            let momInformingClosure: MomInformingHandler.HandlerType = { _ in
                logger.debug("🍽️ Thank God Sam is eating, but he didn't tell me what or when", tag: "eventBus")
            }

            // note it isn't best practice to use a TrackedBusEvent handler when a simpler PayloadHandler works
            // it is also odd to have a double-void service handler that doesn't return any data
            // but to get more test coverage of the send function variations we're using one here
            enum MealMakingHandler: RequestResponseTrackedBusEventHandler {
                // the request payload holds the name of the meal
                typealias RequestPayload = Void
                // the response payload has a summary of what happened in the meal
                typealias ResponsePayload = Void
            }

            // note this is the minimum possible TrackedBusEventHandler for a double-void event
            // it needs to respond with a TrackedBusEvent chained to the inputEvent
            let mealMakingHandlerClosure: MealMakingHandler.HandlerType = { inputEvent in
                await inputEvent.appendEvent(MealMakingHandler.response())
            }

            eventBus.register(
                handlers: [
                    SamMealHandler.handlerRegistration(samMealHandler),
                    MealMakingHandler.handlerRegistration(mealMakingHandlerClosure),
                    MomInformingHandler.handlerRegistration(momInformingClosure),
                ]
            )

            let result = try await SamMealHandler.sendAndWaitForResponse(eventBus: eventBus)
            #expect(result.busEvent.eventType == ObjectIdentifier(SamMealHandler.ResponseEvent.self))
            #expect(result.busEvent.payload == ())

            // this picks the request event out of the sendAndWait result's history
            guard let historyLunchEvent: SamMealHandler.Request = try? result.findFirstEvent(
                ofType: SamMealHandler.requestID
            ) else {
                Issue.record("unexpected nil result on findFirstEvent")
                return
            }
            #expect(historyLunchEvent.eventType == ObjectIdentifier(SamMealHandler.RequestEvent.self))
            #expect(historyLunchEvent.payload == ())

            // this picks the internal MealMaking result event out of the sendAndWait result's history
            guard let historyMealMakingEvent: MealMakingHandler.Response = try? result.findFirstEvent(
                ofType: MealMakingHandler.responseID
            ) else {
                Issue.record("unexpected nil result on findFirstEvent")
                return
            }
            #expect(historyMealMakingEvent.eventType == ObjectIdentifier(MealMakingHandler.ResponseEvent.self))
            #expect(historyMealMakingEvent.payload == ())

            // this picks the internal MomInforming request event out of the sendAndWait result's history
            guard let historyMomInformingEvent: MomInformingHandler.Request = try? result.findFirstEvent(
                ofType: MomInformingHandler.requestID
            ) else {
                Issue.record("unexpected nil result on findFirstEvent")
                return
            }
            #expect(historyMomInformingEvent.eventType == ObjectIdentifier(MomInformingHandler.RequestEvent.self))
            #expect(historyMomInformingEvent.payload == ())
        }
    }
}
