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
@testable import EventBus
import Testing

@Suite("Restart Handler Tests")
struct RestartHandlerTests {
    @Test
    func restartHandlerSingleExecutionCompletes() async throws {
        enum Handler: RequestResponsePayloadHandler {
            typealias RequestPayload = Int
            typealias ResponsePayload = Int
            static let concurrencyType: EventBus.ConcurrencyType = .restart
        }

        let testBus = EventBus()
        let expectedPayload = 42
        testBus.register(handlers: [Handler.handlerRegistration { payload in payload }])

        let response = try await Handler.sendAndWaitForResponse(
            eventBus: testBus,
            payload: expectedPayload,
            timeout: .milliseconds(300)
        )

        #expect(response.busEvent.payload == expectedPayload, "Handler should complete normally for a single event")
    }

    @Test
    func restartTrackedBusEventHandlerSingleExecutionCompletes() async throws {
        enum InnerHandler: RequestResponsePayloadHandler {
            typealias RequestPayload = Int
            typealias ResponsePayload = Int
        }

        enum OuterHandler: RequestResponseTrackedBusEventHandler {
            typealias RequestPayload = Int
            typealias ResponsePayload = Int
            static let concurrencyType: EventBus.ConcurrencyType = .restart
        }

        let testBus = EventBus()
        testBus.register(handlers: [
            InnerHandler.handlerRegistration { payload in payload + 1 },
            OuterHandler.handlerRegistration { inputEvent in
                guard let inner = try await InnerHandler.sendAndWaitForResponse(
                    inputEvent: inputEvent,
                    payload: inputEvent.busEvent.payload
                ) else {
                    return nil
                }
                return await inner.appendEvent(OuterHandler.response(payload: inner.busEvent.payload + 1))
            },
        ])

        let response = try await OuterHandler.sendAndWaitForResponse(
            eventBus: testBus,
            payload: 0,
            timeout: .milliseconds(300)
        )

        #expect(response.busEvent.payload == 2, "Handler should accumulate the payload")
    }

    @Test
    func restartTrackedBusEventHandlerCancelsPrevious() async throws {
        enum Handler: RequestResponsePayloadHandler {
            typealias RequestPayload = Duration
            static let concurrencyType: EventBus.ConcurrencyType = .restart
        }

        let testBus = EventBus()
        let result = LockIsolated<[Duration]>([])
        testBus.register(handlers: [Handler.handlerRegistration { sleepDuration in
            // Skip the await on a zero duration so the last invocation has no suspension
            // points and runs to completion. A restart handler is responsible for designing
            // its own cancellation behavior; under rapid-fire restarts the latest invocation
            // can still be cancelled by a peer if it suspends, so handlers that must always
            // win the race need a synchronous fast path like this one.
            if sleepDuration > .zero {
                try await Task.sleep(for: sleepDuration)
            }
            result.withValue { $0.append(sleepDuration) }
        }])

        // Fire the first event and don't wait. Without restart, its 5s sleep would
        // delay the second event past the 300ms timeout below.
        await Handler.send(eventBus: testBus, payload: .seconds(5))

        // Second event has zero sleep; receiving its response within 100ms proves
        // the restart cancelled the first handler instance before it could append.
        _ = try await Handler.sendAndWaitForResponse(
            eventBus: testBus,
            payload: .zero,
            timeout: .milliseconds(300)
        )

        #expect(result.value.count == 1, "Append should happen only once")
        #expect(result.value.first == .zero, "The only item appended must be from the second event")
    }

    @Test
    func restartHandlerOnlyExecutesTheLastInARow() async throws {
        enum Handler: RequestResponsePayloadHandler {
            typealias RequestPayload = Duration
            static let concurrencyType: EventBus.ConcurrencyType = .restart
        }

        let testBus = EventBus()
        let result = LockIsolated<[Duration]>([])
        testBus.register(handlers: [Handler.handlerRegistration { sleepDuration in
            // Skip the await on a zero duration so the last invocation has no suspension
            // points and runs to completion. A restart handler is responsible for designing
            // its own cancellation behavior; under rapid-fire restarts the latest invocation
            // can still be cancelled by a peer if it suspends, so handlers that must always
            // win the race need a synchronous fast path like this one.
            if sleepDuration > .zero {
                try await Task.sleep(for: sleepDuration)
            }
            result.withValue { $0.append(sleepDuration) }
        }])

        // Fire many long-sleep events. With restart concurrency, each new send
        // cancels the previous in-flight handler before it can append.
        for _ in 0 ..< 99 {
            await Handler.send(eventBus: testBus, payload: .seconds(5))
        }

        // The final event has zero sleep; receiving its response within 300ms proves
        // every prior handler instance was cancelled before its append ran.
        _ = try await Handler.sendAndWaitForResponse(
            eventBus: testBus,
            payload: .zero,
            timeout: .milliseconds(300)
        )

        #expect(result.value.count == 1, "Only one payload should be appended")
        #expect(result.value.first == .zero, "The only item appended must be from the last event")
    }

    @Test
    func restartHandlerCancelsPreviousWithSendAndWait() async throws {
        enum Handler: RequestResponsePayloadHandler {
            typealias RequestPayload = Duration
            static let concurrencyType: EventBus.ConcurrencyType = .restart
        }

        let testBus = EventBus()
        let (handlerEntered, entrySignal) = AsyncStream<Void>.makeStream()
        testBus.register(handlers: [Handler.handlerRegistration { sleepDuration in
            entrySignal.yield()
            if sleepDuration > .zero {
                try await Task.sleep(for: sleepDuration)
            }
        }])

        // The first sendAndWait runs in a Task so the test can move on to send
        // the second event. Its 5s sleep keeps the handler suspended long enough
        // for the second event to cancel it.
        let firstError = LockIsolated<Error?>(nil)
        let firstSendTask = Task {
            do {
                _ = try await Handler.sendAndWaitForResponse(
                    eventBus: testBus,
                    payload: .seconds(5),
                    timeout: .seconds(1)
                )
                Issue.record("first sendAndWait should have thrown after the second event cancelled it")
            } catch {
                firstError.setValue(error)
            }
        }

        // Wait until the first invocation's handler body has started before sending
        // the second event; this guarantees event 2's restart cancels event 1 and
        // not the other way around.
        var entries = handlerEntered.makeAsyncIterator()
        _ = await entries.next()

        // The second event has zero sleep, so it returns immediately after
        // restarting (and cancelling) the first invocation's 5s sleep.
        _ = try await Handler.sendAndWaitForResponse(
            eventBus: testBus,
            payload: .zero,
            timeout: .milliseconds(300)
        )

        // The first sendAndWait should now throw CancellationError, propagated
        // from the cancelled handler back through its subscribed result stream.
        await firstSendTask.value
        #expect(firstError.value is CancellationError)
    }

    @Test
    func restartTrackedBusEventHandlerCancelsPreviousWithSendAndWait() async throws {
        enum Handler: RequestResponseTrackedBusEventHandler {
            typealias RequestPayload = Duration
            static let concurrencyType: EventBus.ConcurrencyType = .restart
        }

        let testBus = EventBus()
        let (handlerEntered, entrySignal) = AsyncStream<Void>.makeStream()
        testBus.register(handlers: [Handler.handlerRegistration { inputEvent in
            entrySignal.yield()
            if inputEvent.busEvent.payload > .zero {
                try await Task.sleep(for: inputEvent.busEvent.payload)
            }
            return await inputEvent.appendEvent(Handler.response())
        }])

        let firstError = LockIsolated<Error?>(nil)
        let firstSendTask = Task {
            do {
                _ = try await Handler.sendAndWaitForResponse(
                    eventBus: testBus,
                    payload: .seconds(5),
                    timeout: .seconds(1)
                )
                Issue.record("first sendAndWait should have thrown after the second event cancelled it")
            } catch {
                firstError.setValue(error)
            }
        }

        var entries = handlerEntered.makeAsyncIterator()
        _ = await entries.next()

        _ = try await Handler.sendAndWaitForResponse(
            eventBus: testBus,
            payload: .zero,
            timeout: .milliseconds(300)
        )

        await firstSendTask.value
        #expect(firstError.value is CancellationError)
    }

    @Test
    func restartHandlerOnlyCancelsMatchingEventType() async throws {
        enum HandlerA: RequestResponsePayloadHandler {
            static let concurrencyType: EventBus.ConcurrencyType = .restart
        }
        enum HandlerB: RequestResponsePayloadHandler {
            static let concurrencyType: EventBus.ConcurrencyType = .restart
        }

        let testBus = EventBus()
        let (handlerAStarted, aStartSignal) = AsyncStream<Void>.makeStream()
        let (releaseHandlerA, aReleaseSignal) = AsyncStream<Void>.makeStream()

        testBus.register(handlers: [
            HandlerA.handlerRegistration {
                aStartSignal.yield()
                for await _ in releaseHandlerA {
                    break
                }
                try Task.checkCancellation()
            },
            HandlerB.handlerRegistration {},
        ])

        let aTask = Task {
            try await HandlerA.sendAndWaitForResponse(eventBus: testBus, timeout: .seconds(1))
        }

        // Wait for HandlerA's invocation to be running so its task is registered as
        // an in-flight restart entry before HandlerB fires.
        var entries = handlerAStarted.makeAsyncIterator()
        _ = await entries.next()

        // HandlerB has a different event type; its restart cancellation iterates the
        // in-flight registry and must skip HandlerA's task. If event-type filtering
        // were broken, HandlerA would be cancelled while suspended below.
        _ = try await HandlerB.sendAndWaitForResponse(eventBus: testBus, timeout: .milliseconds(300))

        // Release HandlerA so its handler can complete normally.
        aReleaseSignal.finish()

        // HandlerA should complete without being cancelled. If HandlerB had wrongly
        // cancelled it, the Task.checkCancellation in the handler would throw and
        // propagate out through aTask.value here.
        _ = try await aTask.value
    }
}
