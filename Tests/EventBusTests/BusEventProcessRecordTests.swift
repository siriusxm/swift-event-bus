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
@Suite("BusEventProcessRecord tests")
struct BusEventProcessRecordTests {
    @Test
    func isLaterInSequenceSingleEvent() {
        #expect(![testEventBusStepRecord0].isLaterInSequence(than: [testEventBusStepRecord1]))
        #expect([testEventBusStepRecord1].isLaterInSequence(than: [testEventBusStepRecord0]))
    }

    @Test
    func isLaterInSequenceMultipleEvents() {
        #expect(
            [testEventBusStepRecord2, testEventBusStepRecord3, testEventBusStepRecord4].isLaterInSequence(
                than: [testEventBusStepRecord0, testEventBusStepRecord1]
            )
        )
        #expect(
            ![testEventBusStepRecord0, testEventBusStepRecord1].isLaterInSequence(
                than: [testEventBusStepRecord2, testEventBusStepRecord3, testEventBusStepRecord4]
            )
        )
        #expect(
            [testEventBusStepRecord0, testEventBusStepRecord2, testEventBusStepRecord4].isLaterInSequence(
                than: [testEventBusStepRecord1, testEventBusStepRecord3]
            )
        )
        #expect(
            [testEventBusStepRecord0, testEventBusStepRecord0, testEventBusStepRecord0, testEventBusStepRecord1].isLaterInSequence(
                than: [testEventBusStepRecord0]
            )
        )
        #expect(
            [testEventBusStepRecord4].isLaterInSequence(
                than: [testEventBusStepRecord1, testEventBusStepRecord2, testEventBusStepRecord3]
            )
        )
        #expect(
            [testEventBusStepRecord1, testEventBusStepRecord3].isLaterInSequence(
                than: [testEventBusStepRecord2]
            )
        )
    }

    @Test
    func isLaterInSequenceSameEvents() {
        #expect(
            ![testEventBusStepRecord0].isLaterInSequence(than: [testEventBusStepRecord0])
        )
        #expect(
            ![testEventBusStepRecord1].isLaterInSequence(than: [testEventBusStepRecord1])
        )
        #expect(
            [testEventBusStepRecord0, testEventBusStepRecord1].isLaterInSequence(than: [testEventBusStepRecord0])
        )
        #expect(
            ![testEventBusStepRecord2, testEventBusStepRecord3, testEventBusStepRecord4].isLaterInSequence(
                than: [testEventBusStepRecord2, testEventBusStepRecord3, testEventBusStepRecord4]
            )
        )
    }

    @Test
    func isLaterInSequenceNilEvents() {
        #expect(![].isLaterInSequence(than: []))
        #expect(
            ![].isLaterInSequence(than: [testEventBusStepRecord0])
        )
        #expect(
            ![testEventBusStepRecord1].isLaterInSequence(than: [])
        )
    }

    @Test
    func isDirectResponseSingleEvents() {
        #expect(![testEventBusStepRecord0].isDirectResponse(to: [testEventBusStepRecord1]))
        #expect(![testEventBusStepRecord1].isDirectResponse(to: [testEventBusStepRecord0]))
    }

    @Test
    func isDirectResponseNonOverlappingEvents() {
        #expect(
            ![testEventBusStepRecord4].isDirectResponse(
                to: [testEventBusStepRecord1, testEventBusStepRecord2, testEventBusStepRecord3]
            )
        )
        #expect(
            ![testEventBusStepRecord1, testEventBusStepRecord3].isDirectResponse(
                to: [testEventBusStepRecord2, testEventBusStepRecord4]
            )
        )
        #expect(
            ![testEventBusStepRecord2, testEventBusStepRecord4].isDirectResponse(
                to: [testEventBusStepRecord1, testEventBusStepRecord3]
            )
        )
    }

    @Test
    func isDirectResponseSuccess() {
        #expect(
            [testEventBusStepRecord1, testEventBusStepRecord4].isDirectResponse(
                to: [testEventBusStepRecord1]
            )
        )
        #expect(
            [testEventBusStepRecord1, testEventBusStepRecord2, testEventBusStepRecord3, testEventBusStepRecord4].isDirectResponse(
                to: [testEventBusStepRecord1, testEventBusStepRecord2, testEventBusStepRecord3]
            )
        )
        #expect(
            [testEventBusStepRecord1, testEventBusStepRecord2, testEventBusStepRecord4].isDirectResponse(
                to: [testEventBusStepRecord1, testEventBusStepRecord2]
            )
        )

        // these are indirect responses
        #expect(
            ![testEventBusStepRecord1, testEventBusStepRecord2, testEventBusStepRecord4].isDirectResponse(
                to: [testEventBusStepRecord1]
            )
        )
        #expect(
            ![testEventBusStepRecord1, testEventBusStepRecord2, testEventBusStepRecord3, testEventBusStepRecord4].isDirectResponse(
                to: [testEventBusStepRecord1, testEventBusStepRecord2]
            )
        )
        #expect(
            ![testEventBusStepRecord1, testEventBusStepRecord2, testEventBusStepRecord3, testEventBusStepRecord4].isDirectResponse(
                to: [testEventBusStepRecord1]
            )
        )
    }

    @Test
    func isDirectResponseNilEvents() {
        #expect(![].isDirectResponse(to: []))
        #expect(
            ![].isDirectResponse(
                to: [testEventBusStepRecord2, testEventBusStepRecord4]
            )
        )
        #expect(
            ![].isDirectResponse(
                to: [testEventBusStepRecord1, testEventBusStepRecord3]
            )
        )
    }

    @Test
    func isIndirectResponseSingleEvents() {
        #expect(![testEventBusStepRecord0].isIndirectResponse(to: [testEventBusStepRecord1]))
        #expect(![testEventBusStepRecord1].isIndirectResponse(to: [testEventBusStepRecord0]))
    }

    @Test
    func isIndirectResponseNonOverlappingEvents() {
        #expect(
            ![testEventBusStepRecord4].isIndirectResponse(
                to: [testEventBusStepRecord1, testEventBusStepRecord2, testEventBusStepRecord3]
            )
        )
        #expect(
            ![testEventBusStepRecord1, testEventBusStepRecord3].isIndirectResponse(
                to: [testEventBusStepRecord2, testEventBusStepRecord4]
            )
        )
        #expect(
            ![testEventBusStepRecord2, testEventBusStepRecord4].isIndirectResponse(
                to: [testEventBusStepRecord1, testEventBusStepRecord3]
            )
        )
    }

    @Test
    func isIndirectResponseSuccess() {
        // these are the same cases as for direct responses, which are valid indirect responses as well
        #expect(
            [testEventBusStepRecord1, testEventBusStepRecord4].isIndirectResponse(
                to: [testEventBusStepRecord1]
            )
        )
        #expect(
            [testEventBusStepRecord1, testEventBusStepRecord2, testEventBusStepRecord3, testEventBusStepRecord4].isIndirectResponse(
                to: [testEventBusStepRecord1, testEventBusStepRecord2, testEventBusStepRecord3]
            )
        )
        #expect(
            [testEventBusStepRecord1, testEventBusStepRecord2, testEventBusStepRecord4].isIndirectResponse(
                to: [testEventBusStepRecord1, testEventBusStepRecord2]
            )
        )

        // these are indirect responses
        #expect(
            [testEventBusStepRecord1, testEventBusStepRecord2, testEventBusStepRecord4].isIndirectResponse(
                to: [testEventBusStepRecord1]
            )
        )
        #expect(
            [testEventBusStepRecord1, testEventBusStepRecord2, testEventBusStepRecord3, testEventBusStepRecord4].isIndirectResponse(
                to: [testEventBusStepRecord1, testEventBusStepRecord2]
            )
        )
        #expect(
            [testEventBusStepRecord1, testEventBusStepRecord2, testEventBusStepRecord3, testEventBusStepRecord4].isIndirectResponse(
                to: [testEventBusStepRecord1]
            )
        )
    }

    @Test
    func isIndirectResponseNilEvents() {
        #expect(![].isIndirectResponse(to: []))
        #expect(
            ![].isIndirectResponse(
                to: [testEventBusStepRecord2, testEventBusStepRecord4]
            )
        )
        #expect(
            ![].isIndirectResponse(
                to: [testEventBusStepRecord1, testEventBusStepRecord3]
            )
        )
    }
}

let testEventBusStepRecord0 = BusEventProcessStepRecord(
    busEvent: testColoredFoodEvent(eventType: "coloredFood1"),
    stepType: .requestWithSend,
    eventSequenceIndex: 0
)
let testEventBusStepRecord1 = BusEventProcessStepRecord(
    busEvent: testColoredFoodEvent(eventType: "coloredFood1"),
    stepType: .requestWithSend,
    eventSequenceIndex: 1
)
let testEventBusStepRecord2 = BusEventProcessStepRecord(
    busEvent: testColoredFoodEvent(eventType: "coloredFood1"),
    stepType: .requestWithSend,
    eventSequenceIndex: 2
)
let testEventBusStepRecord3 = BusEventProcessStepRecord(
    busEvent: testColoredFoodEvent(eventType: "coloredFood1"),
    stepType: .requestWithSend,
    eventSequenceIndex: 3
)
let testEventBusStepRecord4 = BusEventProcessStepRecord(
    busEvent: testColoredFoodEvent(eventType: "coloredFood1"),
    stepType: .requestWithSend,
    eventSequenceIndex: 4
)
// swiftlint:enable no_magic_numbers
