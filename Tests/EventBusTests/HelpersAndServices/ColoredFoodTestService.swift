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

struct TestPayloadWithColoredFood {
    let eventType: String
    let coloredFoodTestRecord: ColoredFoodTestRecord

    init(
        eventType: String = "",
        coloredFoodTestRecord: ColoredFoodTestRecord = ColoredFoodTestRecord()
    ) {
        self.eventType = eventType
        self.coloredFoodTestRecord = coloredFoodTestRecord
    }
}

typealias TestColoredFoodEvent = BusEvent<String, TestPayloadWithColoredFood>
typealias TrackedTestColoredFoodEvent = TrackedBusEvent<String, TestPayloadWithColoredFood>

func testColoredFoodEvent(eventType: String) -> TestColoredFoodEvent {
    TestColoredFoodEvent(eventType: eventType, payload: TestPayloadWithColoredFood())
}

// A reusable class for generating random colored food and testing that the food was generated as expected
// Based on "Green Eggs and Ham" for fun, gives EventBus handlers something testable to do to verify they behaved as expected
actor ColoredFoodTestService {
    static let randomEventBusTestColors = ["Green", "Red", "Orange", "Yellow", "Blue", "Purple", "White", "Black"]
    static let randomEventBusTestFood1 = ["Eggs", "Pancakes", "Chicken", "Pork", "Waffles", "Squid", "Pickles", "Quinona", "Beans"]
    static let randomEventBusTestFood2 = ["Ham", "Ravioli", "Ice Cream", "Toast", "Knishes", "Cabbage", "Beef", "Melon", "Plantains"]

    private var handlerIORecords: [String: [HandlerIORecord]] = [:]

    var handlerIORecordTypeCount: Int {
        handlerIORecords.count
    }

    // MARK: ready-made functions for handlers to call

    func addColorToPayload(
        _ payload: TestPayloadWithColoredFood, outputEventType: String
    ) async -> TestPayloadWithColoredFood {
        // generate new test data, then delegate to common function to do all the rest
        let outputRecord = ColoredFoodTestService.generateColorForRecord(payload.coloredFoodTestRecord)
        return await serviceAddDataToPayload(payload, outputEventType: outputEventType, outputRecord: outputRecord)
    }

    func addFoodToPayload(
        _ payload: TestPayloadWithColoredFood, outputEventType: String
    ) async -> TestPayloadWithColoredFood {
        // generate new test data, then delegate to common function to do all the rest
        let outputRecord = ColoredFoodTestService.generateFoodForRecord(payload.coloredFoodTestRecord)
        return await serviceAddDataToPayload(payload, outputEventType: outputEventType, outputRecord: outputRecord)
    }

    @discardableResult
    func addCritiqueToPayload(
        _ payload: TestPayloadWithColoredFood, outputEventType: String = ""
    ) async -> TestPayloadWithColoredFood {
        // generate new test data, then delegate to common function to do all the rest
        // in this case in message-brokered flows there is no additional event to be chained, so result is discardable
        let outputRecord = ColoredFoodTestService.generateCritiqueForRecord(payload.coloredFoodTestRecord)
        return await serviceAddDataToPayload(payload, outputEventType: outputEventType, outputRecord: outputRecord)
    }

    // MARK: - utilities used in test functions

    // handle common things done in service data adding functions
    private func serviceAddDataToPayload(
        _ payload: TestPayloadWithColoredFood,
        outputEventType: String,
        outputRecord: ColoredFoodTestRecord
    ) async -> TestPayloadWithColoredFood {
        let outputPayload = TestPayloadWithColoredFood(
            eventType: outputEventType,
            coloredFoodTestRecord: outputRecord
        )

        addHandlerIORecord(input: payload.coloredFoodTestRecord, output: outputRecord, eventType: payload.eventType)

        return outputPayload
    }

    private func addHandlerIORecord(input: ColoredFoodTestRecord, output: ColoredFoodTestRecord, eventType: String) {
        let newRecord = HandlerIORecord(input: input, output: output)
        if var records = handlerIORecords[eventType] {
            records.append(newRecord)
            handlerIORecords[eventType] = records
        } else {
            handlerIORecords[eventType] = Array([newRecord])
        }
    }

    func getHandlerIORecordsForService(_ handlerID: String) -> [HandlerIORecord] {
        handlerIORecords[handlerID] ?? []
    }

    private static func generateColorForRecord(_ record: ColoredFoodTestRecord) -> ColoredFoodTestRecord {
        record.updatedWithColor(randomEventBusTestColors.randomElement() ?? "Green")
    }

    static func generateFood() -> String {
        randomEventBusTestFood1.randomElement() ?? "Eggs"
    }

    private static func generateFoodForRecord(_ record: ColoredFoodTestRecord) -> ColoredFoodTestRecord {
        record.updatedWithFood(
            food1: generateFood(),
            food2: randomEventBusTestFood2.randomElement() ?? "Ham"
        )
    }

    private static func generateCritiqueForRecord(_ record: ColoredFoodTestRecord) -> ColoredFoodTestRecord {
        record.updatedWithCritique(critique: criticizeFoodInRecord(record))
    }

    static func isColorValidForRecord(_ record: ColoredFoodTestRecord) -> Bool {
        randomEventBusTestColors.contains(record.color)
    }

    static func isFoodValid(food: String?) -> Bool {
        guard let food else {
            return false
        }
        return randomEventBusTestFood1.contains(food)
    }

    static func isFoodValidForRecord(_ record: ColoredFoodTestRecord) -> Bool {
        randomEventBusTestFood1.contains(record.food1) && randomEventBusTestFood2.contains(record.food2)
    }

    static func isValidRecord(_ record: ColoredFoodTestRecord) -> Bool {
        isColorValidForRecord(record) && isFoodValidForRecord(record)
    }

    private static func criticizeFoodInRecord(_ record: ColoredFoodTestRecord) -> String {
        "\(record.color) \(record.food1) and \(record.food2)? - \(["Yum!", "Yuck!", "Hmmm..."].randomElement() ?? "Yuck!")"
    }
}

struct ColoredFoodTestRecord {
    let color: String
    let food1: String
    let food2: String
    let critique: String

    init(
        color: String = "",
        food1: String = "",
        food2: String = "",
        critique: String = ""
    ) {
        self.color = color
        self.food1 = food1
        self.food2 = food2
        self.critique = critique
    }

    var isBlank: Bool {
        color == "" && food1 == "" && food2 == "" && critique == ""
    }

    var isFoodBlank: Bool {
        food1 == "" && food2 == "" && critique == ""
    }

    var isCritiqueBlank: Bool {
        critique == ""
    }

    func updatedWithColor(_ color: String) -> ColoredFoodTestRecord {
        .init(color: color, food1: food1, food2: food2, critique: critique)
    }

    func updatedWithFood(food1: String, food2: String) -> ColoredFoodTestRecord {
        .init(color: color, food1: food1, food2: food2, critique: critique)
    }

    func updatedWithCritique(critique: String) -> ColoredFoodTestRecord {
        .init(color: color, food1: food1, food2: food2, critique: critique)
    }
}

struct HandlerIORecord {
    let input: ColoredFoodTestRecord
    let output: ColoredFoodTestRecord
}
