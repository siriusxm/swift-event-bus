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

// MARK: - Payload definitions

typealias PipeliningColorAndFood = ColorAndFood
typealias PipeliningColoredFoodSuccess = ColoredFoodSuccess

struct PipeliningExampleError: Error, Sendable, Equatable {
    let message: String

    static let colorServiceFailure = PipeliningExampleError(message: "Color service failure")
    static let foodServiceFailure = PipeliningExampleError(message: "Food service failure")
    static let critiqueServiceFailure = PipeliningExampleError(message: "Critique service failure")
}

typealias PipeliningColoredFoodResult = Result<PipeliningColoredFoodSuccess, PipeliningExampleError>

typealias PipeliningColorAndTwoFoods = ColorAndTwoFoods

// MARK: - Color service and handler

private actor FailingColorSelectionService: ColorSelectionServiceProtocol {
    func selectColor() throws -> String {
        throw PipeliningExampleError.colorServiceFailure
    }
}

private struct ColorSelectionHandler: Sendable {
    let colorService: any ColorSelectionServiceProtocol

    var handlers: [any Handlable] {
        [
            ColorSelectionEvent.SelectColor.handlerRegistration {
                try await colorService.selectColor()
            },
        ]
    }
}

private enum ColorSelectionEvent {
    @RequestResponseHandlerTypes
    enum SelectColor: RequestResponsePayloadHandler {
        typealias ResponsePayload = String
    }
}

// MARK: - Food service and handler

private actor FailingPrimaryFoodSelectionService: PrimaryFoodSelectionServiceProtocol {
    func selectPrimaryFood() throws -> String {
        throw PipeliningExampleError.foodServiceFailure
    }
}

private actor NilSecondaryFoodSelectionService: SecondaryFoodSelectionServiceProtocol {
    func selectSecondaryFood() -> String? {
        nil
    }
}

private struct FoodSelectionHandler: Sendable {
    let primaryFoodService: any PrimaryFoodSelectionServiceProtocol
    let secondaryFoodService: any SecondaryFoodSelectionServiceProtocol

    var handlers: [any Handlable] {
        [
            FoodSelectionEvent.SelectFood.handlerRegistration { color in
                // These independent service calls run in parallel, then this function combines the results when both return.
                async let food1 = primaryFoodService.selectPrimaryFood()
                async let food2 = secondaryFoodService.selectSecondaryFood()
                return try await PipeliningColorAndFood(color: color, food1: food1, food2: food2)
            },
        ]
    }
}

private enum FoodSelectionEvent {
    @RequestResponseHandlerTypes
    enum SelectFood: RequestResponsePayloadHandler {
        typealias RequestPayload = String
        typealias ResponsePayload = PipeliningColorAndFood
    }
}

// MARK: - Critique service and handler

private actor FailingCritiqueWritingService: CritiqueWritingServiceProtocol {
    func singleFoodCritique(color: String, food1: String) throws -> String {
        throw PipeliningExampleError.critiqueServiceFailure
    }

    func doubleFoodCritique(color: String, food1: String, food2: String) throws -> String {
        throw PipeliningExampleError.critiqueServiceFailure
    }
}

private struct CritiqueWritingHandler: Sendable {
    let critiqueService: any CritiqueWritingServiceProtocol

    var handlers: [any Handlable] {
        [
            CritiqueWritingEvent.WriteSingleFoodCritique.handlerRegistration { (payload: PipeliningColorAndFood) in
                try await critiqueService.singleFoodCritique(
                    color: payload.color,
                    food1: payload.food1
                )
            },
            CritiqueWritingEvent.WriteDoubleFoodCritique.handlerRegistration { (payload: PipeliningColorAndTwoFoods) in
                try await critiqueService.doubleFoodCritique(
                    color: payload.color,
                    food1: payload.food1,
                    food2: payload.food2
                )
            },
        ]
    }
}

private enum CritiqueWritingEvent {
    @RequestResponseHandlerTypes
    enum WriteSingleFoodCritique: RequestResponsePayloadHandler {
        typealias RequestPayload = PipeliningColorAndFood
        typealias ResponsePayload = String
    }

    @RequestResponseHandlerTypes
    enum WriteDoubleFoodCritique: RequestResponsePayloadHandler {
        typealias RequestPayload = PipeliningColorAndTwoFoods
        typealias ResponsePayload = String
    }
}

// MARK: - Controller handler and event extensions with pipeline functions

enum PipeliningColoredFoodControllerEvent {
    @RequestResponseHandlerTypes
    enum MakeColoredFood: RequestResponseTrackedBusEventHandler {
        typealias ResponsePayload = PipeliningColoredFoodResult
    }
}

struct PipeliningColoredFoodController: Sendable {
    let handlers: [any Handlable] = [
        PipeliningColoredFoodControllerEvent.MakeColoredFood.handlerRegistration { inputEvent in
            do {
                return try await inputEvent.selectColor()?
                    .selectFood()?
                    .writeCritique()
            } catch let error as PipeliningExampleError {
                return await inputEvent.appendEvent(
                    PipeliningColoredFoodControllerEvent.MakeColoredFood.response(payload: .failure(error))
                )
            }
        },
    ]
}

private extension PipeliningColoredFoodControllerEvent.MakeColoredFood.TrackedRequest {
    func selectColor() async throws -> ColorSelectionEvent.SelectColor.TrackedResponse? {
        try Task.checkCancellation()
        return try await ColorSelectionEvent.SelectColor.sendAndWaitForResponse(inputEvent: self)
    }
}

private extension ColorSelectionEvent.SelectColor.TrackedResponse {
    func selectFood() async throws -> FoodSelectionEvent.SelectFood.TrackedResponse? {
        try Task.checkCancellation()
        return try await FoodSelectionEvent.SelectFood.sendAndWaitForResponse(
            inputEvent: self,
            payload: busEvent.payload
        )
    }
}

extension FoodSelectionEvent.SelectFood.TrackedResponse {
    func writeCritique() async throws -> PipeliningColoredFoodControllerEvent.MakeColoredFood.TrackedResponse? {
        guard let critique = try await requestCritiqueResponse() else {
            return nil
        }
        return await appendEvent(
            PipeliningColoredFoodControllerEvent.MakeColoredFood.response(payload: .success(
                PipeliningColoredFoodSuccess(
                    colorAndFood: busEvent.payload,
                    critique: critique
                )
            ))
        )
    }

    private func requestCritiqueResponse() async throws -> String? {
        try Task.checkCancellation()
        guard let food2 = busEvent.payload.food2 else {
            return try await CritiqueWritingEvent.WriteSingleFoodCritique.sendAndWaitForResponse(
                inputEvent: self,
                payload: busEvent.payload
            )?.busEvent.payload
        }

        return try await CritiqueWritingEvent.WriteDoubleFoodCritique.sendAndWaitForResponse(
            inputEvent: self,
            payload: PipeliningColorAndTwoFoods(
                color: busEvent.payload.color,
                food1: busEvent.payload.food1,
                food2: food2
            )
        )?.busEvent.payload
    }
}

extension EventBusDeepExampleTests {
    @Suite("EventBus pipelining examples")
    struct EventBusDeepExampleTestsPipelining {
        fileprivate func makeEventBus(
            colorService: any ColorSelectionServiceProtocol = ColorSelectionService(),
            primaryFoodService: any PrimaryFoodSelectionServiceProtocol = PrimaryFoodSelectionService(),
            secondaryFoodService: any SecondaryFoodSelectionServiceProtocol,

            critiqueService: any CritiqueWritingServiceProtocol = CritiqueWritingService()
        ) -> EventBus {
            let eventBus = EventBus(defaultTimeout: .milliseconds(300))
            let colorHandler = ColorSelectionHandler(colorService: colorService)
            let foodHandler = FoodSelectionHandler(
                primaryFoodService: primaryFoodService,
                secondaryFoodService: secondaryFoodService
            )
            let critiqueHandler = CritiqueWritingHandler(critiqueService: critiqueService)
            let controller = PipeliningColoredFoodController()
            eventBus.register(handlers: colorHandler.handlers + foodHandler.handlers + critiqueHandler.handlers + controller.handlers)
            return eventBus
        }

        // MARK: - Success tests

        @Test
        func pipelinedControllerFlow() async throws {
            let eventBus = makeEventBus(secondaryFoodService: SecondaryFoodSelectionService())

            let result = try await PipeliningColoredFoodControllerEvent.MakeColoredFood.sendAndWaitForResponse(
                eventBus: eventBus
            )

            let success = try result.busEvent.payload.get()
            #expect(success.colorAndFood.color == "Green")
            #expect(success.colorAndFood.food1 == "Eggs")
            #expect(success.colorAndFood.food2 == "Ham")
            #expect(success.critique == "Green Eggs and Ham sounds memorable.")
            #expect(result.eventHistory.count == 6)
        }

        @Test
        func pipelinedControllerFlowWithoutSecondFood() async throws {
            let eventBus = makeEventBus(secondaryFoodService: NilSecondaryFoodSelectionService())

            let result = try await PipeliningColoredFoodControllerEvent.MakeColoredFood.sendAndWaitForResponse(
                eventBus: eventBus
            )

            let success = try result.busEvent.payload.get()
            #expect(success.colorAndFood.color == "Green")
            #expect(success.colorAndFood.food1 == "Eggs")
            #expect(success.colorAndFood.food2 == nil)
            #expect(success.critique == "Green Eggs sounds memorable.")
            #expect(result.eventHistory.count == 6)
        }

        // MARK: - Failure tests

        @Test
        func pipelinedControllerFlowWhenColorServiceFails() async throws {
            let eventBus = makeEventBus(
                colorService: FailingColorSelectionService(),
                secondaryFoodService: SecondaryFoodSelectionService()
            )

            let result = try await PipeliningColoredFoodControllerEvent.MakeColoredFood.sendAndWaitForResponse(
                eventBus: eventBus
            )

            switch result.busEvent.payload {
            case let .failure(error):
                #expect(error.message == PipeliningExampleError.colorServiceFailure.message)
            case .success:
                Issue.record("Expected color service failure result")
            }
        }

        @Test
        func pipelinedControllerFlowWhenFoodServiceFails() async throws {
            let eventBus = makeEventBus(
                primaryFoodService: FailingPrimaryFoodSelectionService(),
                secondaryFoodService: SecondaryFoodSelectionService()
            )

            let result = try await PipeliningColoredFoodControllerEvent.MakeColoredFood.sendAndWaitForResponse(
                eventBus: eventBus
            )

            switch result.busEvent.payload {
            case let .failure(error):
                #expect(error.message == PipeliningExampleError.foodServiceFailure.message)
            case .success:
                Issue.record("Expected food service failure result")
            }
        }

        @Test
        func pipelinedControllerFlowWhenCritiqueServiceFails() async throws {
            let eventBus = makeEventBus(
                secondaryFoodService: SecondaryFoodSelectionService(),
                critiqueService: FailingCritiqueWritingService()
            )

            let result = try await PipeliningColoredFoodControllerEvent.MakeColoredFood.sendAndWaitForResponse(
                eventBus: eventBus
            )

            switch result.busEvent.payload {
            case let .failure(error):
                #expect(error.message == PipeliningExampleError.critiqueServiceFailure.message)
            case .success:
                Issue.record("Expected critique service failure result")
            }
        }

        @Test
        func pipelineControllerServiceTestInterimResponse() async throws {
            let eventBus = makeEventBus(
                secondaryFoodService: SecondaryFoodSelectionService(),
            )

            enum TestLink: SimpleBusEventLink {
                typealias TriggerEvent = PipeliningColoredFoodControllerEvent.MakeColoredFood.RequestEvent
                typealias ResponseEvent = FoodSelectionEvent.SelectFood.ResponseEvent
            }
            let response = try await TestLink.sendAndWaitForResponse(eventBus: eventBus)

            #expect(response.busEvent.payload.color == "Green")
            #expect(response.busEvent.payload.food1 == "Eggs")
            #expect(response.busEvent.payload.food2 == "Ham")
        }
    }
}
