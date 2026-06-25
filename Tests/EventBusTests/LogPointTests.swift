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

@Suite("LogPoint tests")
struct LogPointTests {
    private enum Constants {
        static let payload = "payload"
        static let formattedPayload = "formatted payload"
        static let alternateFormattedPayload = "alternate formatted payload"
        static let wrongPayload = 42
        static let uniqueConcreteLogPointCount = 2
        static let uniqueAnyLogPointCount = 3
        static let uniqueLogPointTypeCount = 5
        static let wrongEventType = "wrong event type"
        static let errorDescription = "test error"
    }

    private enum TestEvent: Sendable {
        case matching
        case different
    }

    private enum OtherTestEvent: Sendable {
        case matching
    }

    private enum TestError: LocalizedError {
        case first
        case second

        var errorDescription: String? {
            Constants.errorDescription
        }
    }

    @Test
    func logPointMatchesLogPointTypeAndEventType() {
        let logPoint = makeStringLogPoint()

        #expect(logPoint.matches(logPointType: .sent))
        #expect(!logPoint.matches(logPointType: .responded))
        #expect(logPoint.matches(eventType: TestEvent.matching))
        #expect(!logPoint.matches(eventType: TestEvent.different))
        #expect(!logPoint.matches(eventType: Constants.wrongEventType))
    }

    @Test
    func logPointEqualityAndHashingIgnoreFormatterClosure() {
        let logPoint = makeStringLogPoint(formattedPayload: Constants.formattedPayload)
        let equivalentLogPoint = makeStringLogPoint(formattedPayload: Constants.alternateFormattedPayload)
        let differentLogPoint = makeStringLogPoint(logPointType: .responded)

        #expect(logPoint == equivalentLogPoint)
        #expect(logPoint != differentLogPoint)
        #expect(Set([logPoint, equivalentLogPoint, differentLogPoint]).count == Constants.uniqueConcreteLogPointCount)
    }

    @Test
    func erroredLogPointTypesCompareAndHashByCaseOnly() {
        let firstErrorLogPoint = LogPointType.errored(TestError.first)
        let secondErrorLogPoint = LogPointType.errored(TestError.second)
        let uniqueLogPointTypes: Set<LogPointType> = [
            .sent,
            .responded,
            .enteredHandler,
            .exitedHandler,
            firstErrorLogPoint,
            secondErrorLogPoint,
        ]

        #expect(firstErrorLogPoint == secondErrorLogPoint)
        #expect(uniqueLogPointTypes.count == Constants.uniqueLogPointTypeCount)
    }

    @Test
    func anyLogPointMatchesAndFormatsTypedPayloads() {
        let anyLogPoint = AnyLogPoint(makeStringLogPoint())

        #expect(anyLogPoint.matches(TestEvent.matching, .sent))
        #expect(!anyLogPoint.matches(TestEvent.matching, .responded))
        #expect(!anyLogPoint.matches(TestEvent.different, .sent))
        #expect(!anyLogPoint.matches(Constants.wrongEventType, .sent))
        #expect(anyLogPoint.formatPayloadIfPossible(payload: Constants.payload) == Constants.formattedPayload)
        #expect(anyLogPoint.formatPayloadIfPossible(payload: Constants.wrongPayload) == nil)
    }

    @Test
    func anyLogPointEqualityAndHashingUseBoxedBase() {
        let logPoint = AnyLogPoint(makeStringLogPoint(formattedPayload: Constants.formattedPayload))
        let equivalentLogPoint = AnyLogPoint(makeStringLogPoint(formattedPayload: Constants.alternateFormattedPayload))
        let differentLogPoint = AnyLogPoint(makeStringLogPoint(logPointType: .responded))
        let differentBaseLogPoint = AnyLogPoint(
            LogPoint(
                logPointType: .sent,
                eventType: OtherTestEvent.matching,
                formatPayload: { (_: String) in Constants.formattedPayload }
            )
        )

        #expect(logPoint == equivalentLogPoint)
        #expect(logPoint != differentLogPoint)
        #expect(logPoint != differentBaseLogPoint)
        #expect(
            Set([logPoint, equivalentLogPoint, differentLogPoint, differentBaseLogPoint]).count == Constants.uniqueAnyLogPointCount
        )
    }

    @Test
    func logPointBoxEqualityComparesBase() {
        let logPointBox = _LogPointBox(makeStringLogPoint(formattedPayload: Constants.formattedPayload))
        let equivalentLogPointBox = _LogPointBox(makeStringLogPoint(formattedPayload: Constants.alternateFormattedPayload))
        let differentLogPointBox = _LogPointBox(makeStringLogPoint(logPointType: .responded))

        #expect(logPointBox == equivalentLogPointBox)
        #expect(logPointBox != differentLogPointBox)
    }

    private func makeStringLogPoint(
        logPointType: LogPointType = .sent,
        eventType: TestEvent = .matching,
        formattedPayload: String = Constants.formattedPayload
    ) -> LogPoint<TestEvent, String> {
        LogPoint(
            logPointType: logPointType,
            eventType: eventType,
            formatPayload: { (_: String) in formattedPayload }
        )
    }
}
