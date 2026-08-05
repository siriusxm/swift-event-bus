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

@Suite("EventBus logger safety tests")
struct EventBusLoggerSafetyTests {
    private enum Constants {
        static let eventType = "loggerSafetyEvent"
        static let payload = "payload"
        static let sequenceIndex: EventSequenceIndex = 41
    }

    @Test
    func loggerWithoutOutputDoesNotFormatOrLogPayload() {
        let formatterCalled = LockIsolated(false)
        let event = BusEvent(eventType: Constants.eventType, payload: Constants.payload)
        let logger = EventBusLogger(
            logPoints: [
                LogPoint(
                    logPointType: .sent,
                    eventType: Constants.eventType,
                    formatPayload: { (payload: String) in
                        formatterCalled.setValue(true)
                        return payload
                    }
                ),
            ]
        )

        let trackedEvent = trackedEvent(for: event)
        let log = logger.log(trackedEvent.eventHistory, trackedEvent.busEvent, as: .sent)

        #expect(log == nil)
        #expect(!formatterCalled.value)
    }

    @Test
    func configuredOutputReceivesLifecycleMessages() {
        let outputMessages = LockIsolated<[String]>([])
        let event = BusEvent(eventType: Constants.eventType, payload: Constants.payload)
        let logger = EventBusLogger(
            logPoints: [
                LogPoint(
                    logPointType: .sent,
                    eventType: Constants.eventType,
                    formatPayload: { (payload: String) in payload }
                ),
            ],
            output: { message in outputMessages.withValue { $0.append(message) } }
        )

        let trackedEvent = trackedEvent(for: event)
        logger.log(trackedEvent.eventHistory, trackedEvent.busEvent, as: .sent)

        #expect(outputMessages.value.count == 1)
        #expect(outputMessages.value[0].contains(Constants.payload))
    }

    private func trackedEvent(
        for event: BusEvent<String, String>
    ) -> TrackedBusEvent<String, String> {
        TrackedBusEvent(
            eventHistory: [
                BusEventProcessStepRecord(
                    busEvent: event,
                    stepType: .handlerResult,
                    eventSequenceIndex: Constants.sequenceIndex
                ),
            ],
            busEvent: event,
            eventBus: nil
        )
    }
}
