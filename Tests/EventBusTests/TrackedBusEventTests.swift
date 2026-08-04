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
import EventBusTestSupport
import Testing

@Suite("TrackedBusEvent tests")
struct TrackedBusEventTests {
    @Test
    func findFirstEventSuccess() throws {
        let testTrackedBusEvent = TrackedTestColoredFoodEvent(
            eventHistory: [testEventBusStepRecord0, testEventBusStepRecord1, testEventBusStepRecord2],
            busEvent: testColoredFoodEvent(eventType: "coloredFood1"),
            eventBus: nil
        )
        let result: TestColoredFoodEvent = try testTrackedBusEvent.findFirstEvent(ofType: "coloredFood1")
        #expect(result.eventType == "coloredFood1")
    }

    @Test
    func findFirstEventFailMissing() throws {
        do {
            let testTrackedBusEvent = TrackedTestColoredFoodEvent(
                eventHistory: [],
                busEvent: testColoredFoodEvent(eventType: "coloredFood1"),
                eventBus: nil
            )
            let _: TestColoredFoodEvent = try testTrackedBusEvent.findFirstEvent(ofType: "coloredFood2")
            Issue.record("findFirstEvent did not throw error on failure as expected")
        } catch let error as EventBusError {
            #expect(
                error.errorDescription == "findFirstEvent expected event of type coloredFood2 not in history"
            )
        }
    }

    @Test
    func findFirstEventFailWrongType() throws {
        let testStepRecordMismatchPayload = BusEventProcessStepRecord(
            busEvent: BusEvent(eventType: "coloredFood1", payload: 42),
            stepType: .requestWithSend,
            eventSequenceIndex: 0
        )
        do {
            let testTrackedBusEvent = TrackedTestColoredFoodEvent(
                eventHistory: [testStepRecordMismatchPayload],
                busEvent: testColoredFoodEvent(eventType: "coloredFood2"),
                eventBus: nil
            )
            let _: TestColoredFoodEvent = try testTrackedBusEvent.findFirstEvent(ofType: "coloredFood1")
            Issue.record("findFirstEvent did not throw error on failure as expected")
        } catch let error as EventBusError {
            #expect(
                error.errorDescription ==
                    "findFirstEvent event of type coloredFood1 found but was not of expected BusEvent type. " +
                    "Possible payload type mismatch"
            )
        }
    }

    @Test
    func appendEvent() async {
        let testBus = EventBus()
        let testBusEvent1 = testColoredFoodEvent(eventType: "coloredFood1")
        let testTrackedBusEvent1 = TrackedBusEvent(busEvent: testBusEvent1, eventBus: testBus)
        let testBusEvent2 = testColoredFoodEvent(eventType: "coloredFood2")

        let nilEvent = await TrackedTestColoredFoodEvent(
            eventHistory: [],
            busEvent: testBusEvent1,
            eventBus: nil
        ).appendEvent(testBusEvent2)
        #expect(nilEvent == nil)

        let appendedEvent = await testTrackedBusEvent1.appendEvent(testBusEvent2)
        #expect(appendedEvent?.eventHistory.count == 2)
        #expect(appendedEvent?.eventHistory[0].busEvent.eventType as? String == testBusEvent1.eventType)
        #expect(appendedEvent?.eventHistory[1].busEvent.eventType as? String == testBusEvent2.eventType)
    }

    @Test
    func appendEventToTrackedEvent() async {
        let testBus = EventBus()
        let testBusEvent1 = testColoredFoodEvent(eventType: "coloredFood1")
        let testTrackedBusEvent1 = TrackedBusEvent(busEvent: testBusEvent1, eventBus: testBus)
        let testBusEvent2 = testColoredFoodEvent(eventType: "coloredFood2")

        let appendedEvent = await testTrackedBusEvent1.appendEvent(testBusEvent2)
        #expect(appendedEvent?.eventHistory.count == 2)
        #expect(appendedEvent?.eventHistory[0].busEvent.eventType as? String == testBusEvent1.eventType)
        #expect(appendedEvent?.eventHistory[1].busEvent.eventType as? String == testBusEvent2.eventType)
    }

    @Test
    func initWithHistoryPreservesProperties() {
        let testBus = EventBus()
        let testBusEvent = testColoredFoodEvent(eventType: "coloredFood2")
        let testEventHistory = [testEventBusStepRecord0, testEventBusStepRecord1]

        let trackedEvent = TrackedTestColoredFoodEvent(
            eventHistory: testEventHistory,
            busEvent: testBusEvent,
            eventBus: testBus
        )

        #expect(trackedEvent.eventBusCallback != nil)
        #expect(trackedEvent.eventHistory.count == testEventHistory.count)
        #expect(trackedEvent.eventHistory[0].eventSequenceIndex == testEventHistory[0].eventSequenceIndex)
        #expect(trackedEvent.eventHistory[1].eventSequenceIndex == testEventHistory[1].eventSequenceIndex)
        #expect(trackedEvent.eventHistory[0].stepType == testEventHistory[0].stepType)
        #expect(trackedEvent.eventHistory[1].stepType == testEventHistory[1].stepType)
        #expect(trackedEvent.busEvent.eventType == testBusEvent.eventType)
    }

    @Test
    func erasedTrackedBusEvent() throws {
        let testBusEvent = TestColoredFoodEvent(
            eventType: "coloredFood1",
            payload: TestPayloadWithColoredFood(eventType: "payloadEvent")
        )
        let testEventHistory = [testEventBusStepRecord0, testEventBusStepRecord1]
        let testEventWithBus = ErasedTrackedBusEvent(
            eventHistory: testEventHistory,
            busEvent: testBusEvent
        )
        let erasedBusEvent = try #require(testEventWithBus.busEvent as? TestColoredFoodEvent)

        #expect(testEventWithBus.eventHistory.count == testEventHistory.count)
        #expect(testEventWithBus.eventHistory[0].eventSequenceIndex == testEventHistory[0].eventSequenceIndex)
        #expect(testEventWithBus.eventHistory[1].eventSequenceIndex == testEventHistory[1].eventSequenceIndex)
        #expect(erasedBusEvent.eventType == testBusEvent.eventType)
        #expect(erasedBusEvent.payload.eventType == testBusEvent.payload.eventType)
    }
}
