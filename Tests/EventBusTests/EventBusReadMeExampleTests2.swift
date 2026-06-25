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
extension EventBusExampleTests.EventBusReadMeExampleTests {
    @Test
    func readMeExample5() async throws {
        // This example demonstrates a top-level API that is implemented with EventBus events internally.
        // The API does not return until all async work has completed and state has been updated.
        let stateService = StateService()
        let lunchSystem = LunchSystem(
            coloredFoodHandler: ColoredFoodHandler(coloredFoodAPI: ColoredFoodAPI()),
            samLunchHandler: SamLunchHandler(samService: SamService()),
            stateService: stateService
        )

        let before = Date()
        let lunchResult = try await lunchSystem.eatLunchNow()
        let after = Date()

        // After the public API returns, the state service has already received the settled result.
        let recordedResults = await stateService.recordedResults
        let result = try #require(recordedResults.first)
        #expect(recordedResults.count == 1)
        #expect(result.date >= before)
        #expect(result.date <= after)
        #expect(result.lunchResult == "Sam ate Green eggs and ham")
        #expect(lunchResult == "Sam ate Green eggs and ham")
    }

    struct ColoredFoodAPI: Sendable {
        // The external or lower-level API for selecting food can stay ignorant of EventBus.
        func getColoredFood() async -> String {
            "Green eggs and ham"
        }
    }

    struct SamService: Sendable {
        // Sam's eating API is also plain Swift, with no direct dependency on the food API or the EventBus.
        func eatLunch(food: String) async -> String {
            "Sam ate \(food)"
        }
    }

    actor StateService {
        var recordedResults: [(date: Date, lunchResult: String)] = []

        // The state API receives the final settled result of the async process.
        func lunchResults(date: Date, lunchResult: String) {
            recordedResults.append((date: date, lunchResult: lunchResult))
        }
    }

    struct ColoredFoodHandler: Sendable {
        enum GetColoredFood: RequestResponsePayloadHandler {
            typealias ResponsePayload = String
        }

        let coloredFoodAPI: ColoredFoodAPI

        // The handler delegates to its service. EventBus integration stays in the handler.
        var handlers: [any Handlable] {
            [
                GetColoredFood.handlerRegistration { [coloredFoodAPI] in
                    await coloredFoodAPI.getColoredFood()
                },
            ]
        }
    }

    struct SamLunchHandler: Sendable {
        enum EatLunch: RequestResponsePayloadHandler {
            typealias RequestPayload = String
            typealias ResponsePayload = String
        }

        let samService: SamService

        func eatLunchResponse(food: String) async -> String {
            await samService.eatLunch(food: food)
        }

        // This handler delegates to Sam's service and returns the service result through a response event.
        var handlers: [any Handlable] {
            [
                EatLunch.handlerRegistration(eatLunchResponse),
            ]
        }
    }

    struct LunchSystem: Sendable {
        enum EatLunchNow: RequestResponseTrackedBusEventHandler {
            typealias ResponsePayload = String
        }

        let eventBus: EventBus
        let coloredFoodHandler: ColoredFoodHandler
        let samLunchHandler: SamLunchHandler
        let stateService: StateService

        init(
            coloredFoodHandler: ColoredFoodHandler,
            samLunchHandler: SamLunchHandler,
            stateService: StateService
        ) {
            eventBus = EventBus(defaultTimeout: .milliseconds(300))
            self.coloredFoodHandler = coloredFoodHandler
            self.samLunchHandler = samLunchHandler
            self.stateService = stateService
            eventBus.register(handlers: coloredFoodHandler.handlers + samLunchHandler.handlers + handlers)
        }

        // The top-level handler function coordinates the full async operation.
        // It uses TrackedBusEvent APIs so each internal send stays in the same event history.
        var handlers: [any Handlable] {
            [
                EatLunchNow.handlerRegistration { [stateService] inputEvent in
                    guard let foodResponse = try await ColoredFoodHandler.GetColoredFood
                        .sendAndWaitForResponse(inputEvent: inputEvent)
                    else {
                        return nil
                    }

                    guard let lunchResponse = try await SamLunchHandler.EatLunch
                        .sendAndWaitForResponse(
                            inputEvent: foodResponse,
                            payload: foodResponse.busEvent.payload
                        )
                    else {
                        return nil
                    }

                    await stateService.lunchResults(
                        date: Date(),
                        lunchResult: lunchResponse.busEvent.payload
                    )

                    return await lunchResponse.appendEvent(
                        EatLunchNow.response(payload: lunchResponse.busEvent.payload)
                    )
                },
            ]
        }

        // The public API is now a one-line wrapper over its EventBus-backed handler.
        func eatLunchNow() async throws -> String {
            try await EatLunchNow.sendAndWaitForResponse(eventBus: eventBus).busEvent.payload
        }
    }
}

extension EventBusExampleTests.EventBusReadMeExampleTests {
    @Test
    func readMeExample6() async throws {
        // This example demonstrates a decoupled observer that reacts to an internal event.
        // The top-level lunch API never calls the observer directly.

        // In production, callers use the top-level API and do not know about the observer.
        let stateService = StateService()
        let samsMotherService = SamsMotherService()
        let lunchSystem = LunchSystem2(
            coloredFoodHandler: ColoredFoodHandler(coloredFoodAPI: ColoredFoodAPI()),
            samLunchHandler: SamLunchHandler(samService: SamService()),
            samsMotherHandler: SamsMotherHandler(samsMotherService: samsMotherService),
            stateService: stateService
        )
        let lunchResult = try await lunchSystem.eatLunchNow()
        #expect(lunchResult == "Sam ate Green eggs and ham")

        // Tests can use SimpleBusEventLink to wait for the observer's side-effect response deterministically.
        enum LunchObserverTestLink: SimpleBusEventLink {
            typealias TriggerEvent = LunchSystem2.EatLunchNow.RequestEvent
            typealias ResponseEvent = SamsMotherHandler.CheckOnSamsLunch
        }

        let observerResult = try await LunchObserverTestLink.sendAndWaitForResponse(eventBus: lunchSystem.eventBus)
        #expect(observerResult.busEvent.payload == "Sam ate Green eggs and ham, and his mother approved")

        let lunchJudgements = await samsMotherService.lunchJudgements
        #expect(lunchJudgements.contains("Sam ate Green eggs and ham, and his mother approved"))
    }

    actor SamsMotherService {
        var lunchJudgements: [String] = []

        func judgeLunchResult(_ lunchResult: String) -> String {
            let judgement = "\(lunchResult), and his mother approved"
            lunchJudgements.append(judgement)
            return judgement
        }
    }

    struct SamsMotherHandler: Sendable {
        enum CheckOnSamsLunch: ResponsePayloadHandler {
            typealias TriggerEvent = SamLunchHandler.EatLunch.ResponseEvent
            typealias ResponsePayload = String
        }

        let samsMotherService: SamsMotherService

        var handlers: [any Handlable] {
            [
                CheckOnSamsLunch.handlerRegistration { [samsMotherService] lunchResult in
                    await samsMotherService.judgeLunchResult(lunchResult)
                },
            ]
        }
    }

    struct LunchSystem2: Sendable {
        enum EatLunchNow: RequestResponseTrackedBusEventHandler {
            typealias ResponsePayload = String
        }

        let eventBus: EventBus
        let coloredFoodHandler: ColoredFoodHandler
        let samLunchHandler: SamLunchHandler
        let samsMotherHandler: SamsMotherHandler
        let stateService: StateService

        init(
            coloredFoodHandler: ColoredFoodHandler,
            samLunchHandler: SamLunchHandler,
            samsMotherHandler: SamsMotherHandler,
            stateService: StateService
        ) {
            eventBus = EventBus(defaultTimeout: .milliseconds(300))
            self.coloredFoodHandler = coloredFoodHandler
            self.samLunchHandler = samLunchHandler
            self.samsMotherHandler = samsMotherHandler
            self.stateService = stateService
            eventBus.register(
                handlers: coloredFoodHandler.handlers + samLunchHandler.handlers + samsMotherHandler.handlers + handlers
            )
        }

        // This handler has no reference to SamsMotherHandler.
        // The observer is decoupled because it listens for SamLunchHandler.EatLunch.ResponseEvent.
        var handlers: [any Handlable] {
            [
                EatLunchNow.handlerRegistration { [stateService] inputEvent in
                    guard let foodResponse = try await ColoredFoodHandler.GetColoredFood
                        .sendAndWaitForResponse(inputEvent: inputEvent)
                    else {
                        return nil
                    }

                    guard let lunchResponse = try await SamLunchHandler.EatLunch
                        .sendAndWaitForResponse(
                            inputEvent: foodResponse,
                            payload: foodResponse.busEvent.payload
                        )
                    else {
                        return nil
                    }

                    await stateService.lunchResults(
                        date: Date(),
                        lunchResult: lunchResponse.busEvent.payload
                    )

                    return await lunchResponse.appendEvent(
                        EatLunchNow.response(payload: lunchResponse.busEvent.payload)
                    )
                },
            ]
        }

        func eatLunchNow() async throws -> String {
            try await EatLunchNow.sendAndWaitForResponse(eventBus: eventBus).busEvent.payload
        }
    }
}

// swiftlint:enable no_magic_numbers
