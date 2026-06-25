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

import ConcurrencyExtras
import EventBus

struct MockEventSavingBusLogger: EventBusLoggable {
    private let events = LockIsolated<[AnyTrackedBusEventType]>([])

    func latestEvents() -> [AnyTrackedBusEventType] {
        events.withValue { $0 }
    }

    func clearEvents() {
        events.withValue { $0.removeAll() }
    }

    private func append(_ event: AnyTrackedBusEventType) {
        events.withValue { $0.append(event) }
    }

    @discardableResult
    func log(
        _ trackedEvent: AnyTrackedBusEventType,
        as logPoint: LogPointType
    ) -> String? {
        append(trackedEvent)
        return nil
    }

    @discardableResult
    func log(
        _ erasedEvent: ErasedTrackedBusEvent,
        as logPoint: LogPointType
    ) -> String? {
        // ignore ErasedTrackedBusEvent in this mock
        nil
    }
}
