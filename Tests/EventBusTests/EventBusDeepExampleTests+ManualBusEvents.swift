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

private struct ManualColoredFoodPayload: Sendable, Equatable {
    let color: String?
    let food: String?
    let critique: String?
}

private typealias ManualColoredFoodEvent = BusEvent<ManualBusEventType, ManualColoredFoodPayload>
private typealias TrackedManualColoredFoodEvent = TrackedBusEvent<ManualBusEventType, ManualColoredFoodPayload>

// MARK: - Legacy event definitions

// These are meant to simulate an event enum that was defined in a legacy system
// ..and you are adapting EventBus handlers to integrate into that system.
// Otherwise, if you have a greenfield system to create, better to use SimpleBusEventType and related.
private enum ManualBusEventType: String, Sendable {
    case getColor
    case getFood
    case getCritique
    case complete
}

// MARK: - Color service and handler

private protocol ColorServiceProtocol: Sendable {
    func getColor() async -> String
}

private actor ColorService: ColorServiceProtocol {
    func getColor() -> String {
        "Green"
    }
}

private struct ColorHandler: Sendable {
    let colorService: any ColorServiceProtocol

    @Sendable func handle(_ payload: ManualColoredFoodPayload) async throws -> [ManualColoredFoodEvent] {
        await [
            ManualColoredFoodEvent(
                eventType: .getFood,
                payload: ManualColoredFoodPayload(
                    color: colorService.getColor(),
                    food: payload.food,
                    critique: payload.critique
                )
            ),
        ]
    }
}

// MARK: - Food service and handler

private protocol FoodServiceProtocol: Sendable {
    func getFood() async -> String
}

private actor FoodService: FoodServiceProtocol {
    func getFood() -> String {
        "Eggs"
    }
}

private struct FoodHandler: Sendable {
    let foodService: any FoodServiceProtocol

    @Sendable func handle(_ payload: ManualColoredFoodPayload) async throws -> [ManualColoredFoodEvent] {
        await [
            ManualColoredFoodEvent(
                eventType: .getCritique,
                payload: ManualColoredFoodPayload(
                    color: payload.color,
                    food: foodService.getFood(),
                    critique: payload.critique
                )
            ),
        ]
    }
}

// MARK: - Critique service and handler

private protocol CritiqueServiceProtocol: Sendable {
    func getCritique(color: String, food: String) async -> String
}

private actor CritiqueService: CritiqueServiceProtocol {
    func getCritique(color: String, food: String) -> String {
        "\(color) \(food) sounds memorable."
    }
}

private struct CritiqueHandler: Sendable {
    let critiqueService: any CritiqueServiceProtocol

    @Sendable func handle(_ payload: ManualColoredFoodPayload) async throws -> [ManualColoredFoodEvent] {
        guard let color = payload.color, let food = payload.food else {
            return []
        }

        return await [
            ManualColoredFoodEvent(
                eventType: .complete,
                payload: ManualColoredFoodPayload(
                    color: color,
                    food: food,
                    critique: critiqueService.getCritique(color: color, food: food)
                )
            ),
        ]
    }
}

extension EventBusDeepExampleTests {
    @Suite("EventBus manual bus event examples")
    struct EventBusDeepExampleTestsManualBusEvents {
        @Test
        func manualBusEventIntegration() async throws {
            let eventBus = EventBus(defaultTimeout: .milliseconds(300))
            let colorHandler = ColorHandler(colorService: ColorService())
            let foodHandler = FoodHandler(foodService: FoodService())
            let critiqueHandler = CritiqueHandler(critiqueService: CritiqueService())

            eventBus.add(
                .parallel,
                handler: colorHandler.handle,
                eventType: ManualBusEventType.getColor,
                serviceName: "colorService"
            )
            eventBus.add(
                .parallel,
                handler: foodHandler.handle,
                eventType: ManualBusEventType.getFood,
                serviceName: "foodService"
            )
            eventBus.add(
                .parallel,
                handler: critiqueHandler.handle,
                eventType: ManualBusEventType.getCritique,
                serviceName: "critiqueService"
            )

            let result: TrackedManualColoredFoodEvent = try await eventBus.sendAndWaitForMatchingResult(
                ManualColoredFoodEvent(
                    eventType: .getColor,
                    payload: ManualColoredFoodPayload(
                        color: nil,
                        food: nil,
                        critique: nil
                    )
                ),
                resultType: ManualBusEventType.complete,
                matchingOptions: [.matchResponse(.indirect)],
                timeout: .milliseconds(300)
            )

            #expect(result.busEvent.payload.color == "Green")
            #expect(result.busEvent.payload.food == "Eggs")
            #expect(result.busEvent.payload.critique == "Green Eggs sounds memorable.")
            #expect(result.busEvent.eventType == .complete)
        }
    }
}
