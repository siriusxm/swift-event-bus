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

struct ColorAndFood: Sendable, Equatable {
    let color: String
    let food1: String
    let food2: String?
}

struct ColorAndTwoFoods: Sendable, Equatable {
    let color: String
    let food1: String
    let food2: String
}

struct ColoredFoodSuccess: Sendable, Equatable {
    let colorAndFood: ColorAndFood
    let critique: String
}

protocol ColorSelectionServiceProtocol: Sendable {
    func selectColor() async throws -> String
}

actor ColorSelectionService: ColorSelectionServiceProtocol {
    func selectColor() throws -> String {
        "Green"
    }
}

protocol PrimaryFoodSelectionServiceProtocol: Sendable {
    func selectPrimaryFood() async throws -> String
}

actor PrimaryFoodSelectionService: PrimaryFoodSelectionServiceProtocol {
    func selectPrimaryFood() throws -> String {
        "Eggs"
    }
}

protocol SecondaryFoodSelectionServiceProtocol: Sendable {
    func selectSecondaryFood() async -> String?
}

actor SecondaryFoodSelectionService: SecondaryFoodSelectionServiceProtocol {
    func selectSecondaryFood() -> String? {
        "Ham"
    }
}

protocol CritiqueWritingServiceProtocol: Sendable {
    func singleFoodCritique(color: String, food1: String) async throws -> String
    func doubleFoodCritique(color: String, food1: String, food2: String) async throws -> String
}

actor CritiqueWritingService: CritiqueWritingServiceProtocol {
    func singleFoodCritique(color: String, food1: String) throws -> String {
        "\(color) \(food1) sounds memorable."
    }

    func doubleFoodCritique(color: String, food1: String, food2: String) throws -> String {
        "\(color) \(food1) and \(food2) sounds memorable."
    }
}
