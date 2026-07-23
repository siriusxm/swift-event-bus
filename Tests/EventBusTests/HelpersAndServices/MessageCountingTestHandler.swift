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

enum CountingTestMatchingHandler: RequestResponsePayloadHandler {
    typealias ResponsePayload = ObjectIdentifier
    static let serviceName = "CountingTestMatchingService"
}

enum CountingTestNonMatchingHandler: RequestResponsePayloadHandler {
    typealias ResponsePayload = ObjectIdentifier
    static let serviceName = "CountingTestNonMatchingService"
}

/// Normally, best practice is to separate the service from its handler so the service can be isolated from dependencies on the EventBus
/// But in this case, we are using this to test the EventBus directly, so this is the simplest way to provide a test handler with the least boilerplate
actor MessageCountingTestHandler: Sendable {
    private(set) var handledEvents: [ObjectIdentifier: Int] = [:]

    @Sendable func handle(_: CountingTestMatchingHandler.RequestPayload) async throws -> CountingTestMatchingHandler.ResponsePayload {
        let eventID = CountingTestMatchingHandler.requestID
        handledEvents[eventID, default: 0] += 1
        return eventID
    }
}
