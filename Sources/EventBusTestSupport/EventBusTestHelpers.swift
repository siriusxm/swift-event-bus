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

import EventBus

public extension TrackedBusEventType {
    func findFirstEvent<OtherEventType: Equatable & Sendable, OtherPayload: Sendable>(
        ofType eventType: OtherEventType
    ) throws -> BusEvent<OtherEventType, OtherPayload> {
        let queryResult = eventHistory.first(where: {
            ($0.busEvent.eventType as? OtherEventType) == eventType
        })
        guard let result = queryResult?.busEvent as? BusEvent<OtherEventType, OtherPayload> else {
            let description = queryResult == nil
                ? "findFirstEvent expected event of type \(eventType) not in history"
                : "findFirstEvent event of type \(eventType) found but was not of expected BusEvent type. " +
                "Possible payload type mismatch"
            throw EventBusError.unexpectedError(description)
        }
        return result
    }
}
