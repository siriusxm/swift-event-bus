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

import Combine
@testable import EventBus
import Foundation
import Testing

// swiftformat:disable hoistAwait
@Suite("EventStreamHandlerManager tests")
struct EventStreamHandlerManagerTests {
    @Test
    func addAndRemoveHandler() async throws {
        let eventBus = EventBus()
        let testHandler = MessageCountingTestHandler()

        // ensure EventBus starts with no unexpected handlers registered
        #expect(eventBus.handlerIDs(for: CountingTestMatchingHandler.serviceName).isEmpty)

        // send messages before the handler is registered (should not be counted)
        await CountingTestMatchingHandler.send(eventBus: eventBus)
        await CountingTestNonMatchingHandler.send(eventBus: eventBus)

        // register a test handler
        eventBus.register(handlers: [CountingTestMatchingHandler.handlerRegistration(testHandler.handle)])

        // now check EventBus reports the handler registered as expected
        #expect(eventBus.handlerIDs(for: CountingTestMatchingHandler.serviceName).count == 1)
        let handlerID = try #require(eventBus.handlerIDs(for: CountingTestMatchingHandler.serviceName).first)

        // now send the handler some messages that it should handle and an equal number that it shouldn't
        let maxIterations = 7
        try await repeatThrowingVoidGroupTasks(maxIterations) {
            await CountingTestNonMatchingHandler.send(eventBus: eventBus)
            let response = try await CountingTestMatchingHandler.sendAndWaitForResponse(
                eventBus: eventBus,
                timeout: .milliseconds(300)
            )
            // check each response is as expected as test runs
            #expect(response.busEvent.payload == CountingTestMatchingHandler.requestID)
            #expect(response.busEvent.eventType == CountingTestMatchingHandler.responseID)
        }

        // de-register handler (should not race with above which should be done)
        eventBus.remove(handler: handlerID)

        // now check EventBus reports the handler removed as expected
        #expect(eventBus.handlerIDs(for: CountingTestMatchingHandler.serviceName).isEmpty)

        // send messages after the handler is removed (should not be counted)
        await CountingTestMatchingHandler.send(eventBus: eventBus)
        await CountingTestNonMatchingHandler.send(eventBus: eventBus)

        // now check if the counts are as expected, only matching events sent while the handler was registered should be counted
        #expect(await testHandler.handledEvents[CountingTestMatchingHandler.requestID] == maxIterations)
        #expect(await testHandler.handledEvents.values.reduce(0, +) == maxIterations)
        #expect(await testHandler.handledEvents[CountingTestNonMatchingHandler.requestID] == nil)
    }

    @Test
    func addAndRemoveHandlersByService() throws {
        let testBus = EventBus()

        enum FirstServiceHandler: RequestResponsePayloadHandler {
            typealias ResponsePayload = ObjectIdentifier
            static let serviceName = "Service1"
        }

        enum SecondServiceHandler: RequestResponsePayloadHandler {
            typealias ResponsePayload = ObjectIdentifier
            static let serviceName = "Service2"
        }

        let firstServiceHandler: FirstServiceHandler.HandlerType = { _ in FirstServiceHandler.requestID }
        let secondServiceHandler: SecondServiceHandler.HandlerType = { _ in SecondServiceHandler.requestID }

        // add a service with 3 handlers
        testBus.register(handlers: [
            FirstServiceHandler.handlerRegistration(firstServiceHandler),
            FirstServiceHandler.handlerRegistration(firstServiceHandler),
            FirstServiceHandler.handlerRegistration(firstServiceHandler),
        ])

        // now check handlers added as expected
        #expect(testBus.handlerIDs(for: FirstServiceHandler.serviceName).count == 3)

        // add a second service with 4 handlers
        testBus.register(handlers: [
            SecondServiceHandler.handlerRegistration(secondServiceHandler),
            SecondServiceHandler.handlerRegistration(secondServiceHandler),
            SecondServiceHandler.handlerRegistration(secondServiceHandler),
            SecondServiceHandler.handlerRegistration(secondServiceHandler),
        ])
        let handlerID = try #require(testBus.handlerIDs(for: SecondServiceHandler.serviceName).first)

        // now check both services have the expected number of handlers registered
        #expect(testBus.handlerIDs(for: FirstServiceHandler.serviceName).count == 3)
        #expect(testBus.handlerIDs(for: SecondServiceHandler.serviceName).count == 4)
        #expect(testBus.handlerIDs(for: "Rando").isEmpty)

        // remove one handler from one of the services
        testBus.remove(handler: handlerID)

        // now recheck both services have the expected number of handlers registered after one handler removed
        #expect(testBus.handlerIDs(for: FirstServiceHandler.serviceName).count == 3)
        #expect(testBus.handlerIDs(for: SecondServiceHandler.serviceName).count == 3)

        // now remove all of service 1 and re-check counts again
        testBus.remove(service: FirstServiceHandler.serviceName)
        #expect(testBus.handlerIDs(for: FirstServiceHandler.serviceName).isEmpty)
        #expect(testBus.handlerIDs(for: SecondServiceHandler.serviceName).count == 3)

        // finally remove rest of service2 handlers, so now all handler counts should be zero
        testBus.remove(service: SecondServiceHandler.serviceName)
        #expect(testBus.handlerIDs(for: FirstServiceHandler.serviceName).isEmpty)
        #expect(testBus.handlerIDs(for: SecondServiceHandler.serviceName).isEmpty)
    }

    @Test
    func removeHandlersByEventTypeAndServiceName() {
        let testBus = EventBus()

        enum FirstSharedServiceHandler: RequestResponsePayloadHandler {
            typealias ResponsePayload = ObjectIdentifier
            static let serviceName = "SharedService"
        }

        enum SecondSharedServiceHandler: RequestResponsePayloadHandler {
            typealias ResponsePayload = ObjectIdentifier
            static let serviceName = "SharedService"
        }

        let firstHandler: FirstSharedServiceHandler.HandlerType = { _ in FirstSharedServiceHandler.requestID }
        let secondHandler: SecondSharedServiceHandler.HandlerType = { _ in SecondSharedServiceHandler.requestID }

        testBus.register(handlers: [
            FirstSharedServiceHandler.handlerRegistration(firstHandler),
            FirstSharedServiceHandler.handlerRegistration(firstHandler),
            SecondSharedServiceHandler.handlerRegistration(secondHandler),
            SecondSharedServiceHandler.handlerRegistration(secondHandler),
            SecondSharedServiceHandler.handlerRegistration(secondHandler),
        ])

        #expect(testBus.handlerIDs(for: FirstSharedServiceHandler.serviceName).count == 5)

        testBus.remove(
            for: FirstSharedServiceHandler.requestID,
            serviceName: FirstSharedServiceHandler.serviceName
        )
        #expect(testBus.handlerIDs(for: FirstSharedServiceHandler.serviceName).count == 3)

        testBus.remove(
            for: SecondSharedServiceHandler.requestID,
            serviceName: SecondSharedServiceHandler.serviceName
        )
        #expect(testBus.handlerIDs(for: SecondSharedServiceHandler.serviceName).isEmpty)
    }
}

// swiftformat:enable hoistAwait
