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

import Foundation

public enum BusEventStepType: String, Sendable {
    case requestWithSend
    case requestWithSendAndWait
    case handlerResult
    case handlerError
}

public enum BusEventMatchingOption: Sendable {
    public enum ResponseOption: Sendable {
        // request must be immediately before the response in event history
        // (use with caution, can be broken when process is refactored)
        case direct
        // request can be anywhere before response in response's event history
        case indirect
    }

    // match only responses to a specific request instance
    case matchResponse(ResponseOption)
}

/// records a single step in processing a BusEvent, either sending into the bus as a request, or being handled by a handler
public struct BusEventProcessStepRecord: Sendable {
    public let busEvent: any BusEventType
    public let stepType: BusEventStepType
    public let eventSequenceIndex: EventSequenceIndex
}

/// records a chain of processing steps for a series of related events
public typealias BusEventProcessRecord = [BusEventProcessStepRecord]

// These history records are exposed publicly for callers to pass back to the bus when chaining events,
// but they are read-only for callers. Only internal bus functions can create or append to history records.
extension BusEventProcessRecord {
    // convenience method for reading current (most recent) BusEvent
    public var busEvent: (any BusEventType)? {
        last?.busEvent
    }

    public var currentEventSequenceIndex: EventSequenceIndex? {
        last?.eventSequenceIndex
    }

    func isLaterInSequence(than requestHistoryToMatch: BusEventProcessRecord) -> Bool {
        guard let mySequenceIndex = last?.eventSequenceIndex,
              let otherSequenceIndex = requestHistoryToMatch.last?.eventSequenceIndex
        else {
            return false
        }
        return mySequenceIndex > otherSequenceIndex
    }

    func isDirectResponse(to requestHistoryToMatch: BusEventProcessRecord) -> Bool {
        // fail-safe test for nil - neither should be nil, but don't want to return true if both are
        let secondToLastStepIndexOffset = -2
        guard let requestInHistory = self[safeIndex: count + secondToLastStepIndexOffset],
              // the relevant event to match is the last one in the history array (i.e. the latest event in the request chain)
              let expectedRequest = requestHistoryToMatch.last
        else {
            return false
        }
        return requestInHistory.eventSequenceIndex == expectedRequest.eventSequenceIndex
    }

    func isIndirectResponse(to requestHistoryToMatch: BusEventProcessRecord) -> Bool {
        // the relevant event to match is the last one in the history array (i.e. the latest event in the request chain)
        guard let expectedRequest = requestHistoryToMatch.last,
              isLaterInSequence(than: requestHistoryToMatch)
        else {
            return false
        }
        return contains { $0.eventSequenceIndex == expectedRequest.eventSequenceIndex }
    }

    func matchAndTypeEvent<EventType: Equatable & Sendable, Payload: Sendable>(
        _ eventTypeToMatch: some Equatable & Sendable,
        _ eventBus: EventBus
    ) -> (TrackedBusEvent<EventType, Payload>)? {
        if let typedEvent = busEvent as? any BusEventType<EventType, Payload>,
           typedEvent.eventType == eventTypeToMatch as? EventType
        {
            return TrackedBusEvent(eventHistory: self, busEvent: typedEvent, eventBus: eventBus)
        }
        return nil
    }

    // Currently the only "matching" results are direct or indirect response to a request, so only one option is allowed.
    func matchResponseWithOptions(
        to requestHistoryToMatch: BusEventProcessRecord, matchingOptions: [BusEventMatchingOption]
    ) -> Bool {
        // if no matching options provided, anything non-nil matches
        guard let option = matchingOptions.first else {
            return !isEmpty && !requestHistoryToMatch.isEmpty
        }

        switch option {
        case let .matchResponse(responseOption):
            switch responseOption {
            case .direct:
                return isDirectResponse(to: requestHistoryToMatch)
            case .indirect:
                return isIndirectResponse(to: requestHistoryToMatch)
            }
        }
    }
}
