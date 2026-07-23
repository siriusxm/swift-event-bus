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
import Foundation
import Testing

extension EventBusDeepExampleTests {
    @Suite("EventBus concurrency type examples")
    struct EventBusDeepExampleTestsConcurrencyTypes {
        // For an example of the .parallel concurrencyType in use, see
        // EventBusExampleTests.EventBusReadMeExampleTests.readMeExample1.
        // .parallel is the default for handler protocols, so every example in
        // the README is also a .parallel example.

        // MARK: - Serial access

        // The next two tests show the most common .serial use case: ensuring
        // that a service's internal mutable state is only accessed by one handler
        // invocation at a time. There are two ways to do this, with the
        // serialization living in different places.

        @Test
        func serialAccessViaActorService() async throws {
            // Pattern A: the service is an actor, so the service itself enforces
            // serial access to its mutable state. The handler can be .parallel
            // (the default) — the actor's mailbox handles queueing on its own.
            actor PlaybackQueue {
                private(set) var tracks: [Int] = []
                func append(_ trackID: Int) {
                    tracks.append(trackID)
                }
            }

            @RequestResponseHandlerTypes
            enum EnqueueTrack: RequestResponsePayloadHandler {
                typealias RequestPayload = Int
                // .parallel is the default; the actor below provides serialization.
            }

            let queue = PlaybackQueue()
            let eventBus = EventBus(defaultTimeout: .seconds(1))
            eventBus.register(handlers: [EnqueueTrack.handlerRegistration { trackID in
                await queue.append(trackID)
            }])

            // Send all four events as concurrent sendAndWaits, then wait for every
            // one to complete before asserting. Under .parallel each handler runs
            // in its own task, so we cannot rely on a single trailing sendAndWait
            // to imply earlier handler tasks have finished — they may still be
            // in flight when the trailing one publishes its response.
            try await withThrowingTaskGroup(of: Void.self) { group in
                for trackID in 1 ... 4 {
                    group.addTask {
                        _ = try await EnqueueTrack.sendAndWaitForResponse(
                            eventBus: eventBus,
                            payload: trackID,
                            timeout: .seconds(1)
                        )
                    }
                }
                try await group.waitForAll()
            }

            // The set of tracks is fully populated with no data corruption. Note
            // that the *order* of the appends is not guaranteed under .parallel —
            // the handler tasks race for which one calls the actor first. If
            // ordering matters as well as correctness, use Pattern B instead.
            let orderedResult = await Set(queue.tracks)
            #expect(orderedResult == [1, 2, 3, 4])
        }

        @Test
        func serialAccessViaSerialHandler() async throws {
            // Pattern B: the service has no internal serialization. The handler
            // declares concurrencyType = .serial so the EventBus runs invocations
            // one at a time, providing the serialization at the handler boundary.
            // This pattern also preserves the order of arriving events, since the
            // bus dispatches them FIFO.
            final class PlaybackQueue: @unchecked Sendable {
                private(set) var tracks: [Int] = []
                func append(_ trackID: Int) {
                    tracks.append(trackID)
                }
            }

            @RequestResponseHandlerTypes
            enum EnqueueTrack: RequestResponsePayloadHandler {
                typealias RequestPayload = Int
                static let concurrencyType: EventBus.ConcurrencyType = .serial
            }

            let queue = PlaybackQueue()
            let eventBus = EventBus(defaultTimeout: .seconds(1))
            eventBus.register(handlers: [EnqueueTrack.handlerRegistration { trackID in
                queue.append(trackID)
            }])

            for trackID in 1 ... 3 {
                await EnqueueTrack.send(eventBus: eventBus, payload: trackID)
            }
            _ = try await EnqueueTrack.sendAndWaitForResponse(
                eventBus: eventBus,
                payload: 4,
                timeout: .seconds(1)
            )

            // .serial preserves arrival order, so this assertion is sequence-exact.
            #expect(queue.tracks == [1, 2, 3, 4])
        }

        @Test
        func serialTrackedBusEventHandler() async throws {
            // Pattern C: the outer handler is still responsible for serial access
            // to mutable state, but the outer function needs to call another
            // EventBus handler as part of its work. The inner handler can remain
            // .parallel because the serial outer handler decides when its result
            // is applied to the queue.
            final class PlaybackQueue: @unchecked Sendable {
                private(set) var tracks: [Int] = []
                func append(_ trackID: Int) {
                    tracks.append(trackID)
                }
            }

            @RequestResponseHandlerTypes
            enum NormalizeTrack: RequestResponsePayloadHandler {
                typealias RequestPayload = Int
                typealias ResponsePayload = Int
                // .parallel is the default; the serial outer handler controls access.
            }

            @RequestResponseHandlerTypes
            enum EnqueueTrack: RequestResponseTrackedBusEventHandler {
                typealias RequestPayload = Int
                typealias ResponsePayload = Int
                static let concurrencyType: EventBus.ConcurrencyType = .serial
            }

            let queue = PlaybackQueue()
            let eventBus = EventBus(defaultTimeout: .seconds(1))
            eventBus.register(handlers: [
                NormalizeTrack.handlerRegistration { trackID in
                    trackID * 10
                },
                EnqueueTrack.handlerRegistration { inputEvent in
                    guard let normalizedTrack = try await NormalizeTrack.sendAndWaitForResponse(
                        inputEvent: inputEvent,
                        payload: inputEvent.busEvent.payload,
                        timeout: .seconds(1)
                    ) else {
                        return nil
                    }
                    queue.append(normalizedTrack.busEvent.payload)
                    return await normalizedTrack.appendEvent(
                        EnqueueTrack.response(payload: normalizedTrack.busEvent.payload)
                    )
                },
            ])

            // As in Pattern B, the final sendAndWait re-synchronizes the test
            // after the first three fire-and-forget events have queued.
            for trackID in 1 ... 3 {
                await EnqueueTrack.send(eventBus: eventBus, payload: trackID)
            }
            let response = try await EnqueueTrack.sendAndWaitForResponse(
                eventBus: eventBus,
                payload: 4,
                timeout: .seconds(1)
            )

            // The outer tracked handler preserves queue mutation order even
            // though the inner normalization handler uses default .parallel.
            #expect(response.busEvent.payload == 40)
            #expect(queue.tracks == [10, 20, 30, 40])
        }

        // MARK: - Restart

        @Test
        func restartHandlerCancelsCleanly() async throws {
            // A well-written .restart handler reaches a suspension point promptly
            // so that when a new event arrives, the previous invocation can be
            // cancelled cleanly without leaving partial work behind.
            //
            // In this search-as-you-type example, the handler body is:
            //   1. A small debounce sleep, so rapid keystrokes coalesce.
            //   2. A backend fetch, which is itself cancellable.
            // Both `Task.sleep` and the actor `await` throw CancellationError at
            // their suspension points if the task is cancelled, so the handler
            // unwinds naturally without the author having to write any cleanup code.
            actor SearchBackend {
                func fetchResults(for query: String) async throws -> [String] {
                    // A real backend call is itself cancellable; a sleep stands in
                    // for the network round-trip in this example.
                    try await Task.sleep(for: .milliseconds(20))
                    return ["result for \(query)"]
                }
            }

            @RequestResponseHandlerTypes
            enum Search: RequestResponsePayloadHandler {
                typealias RequestPayload = String
                typealias ResponsePayload = [String]
                static let concurrencyType: EventBus.ConcurrencyType = .restart
            }

            let backend = SearchBackend()
            let eventBus = EventBus(defaultTimeout: .seconds(1))
            eventBus.register(handlers: [Search.handlerRegistration { query in
                // Debounce: if the user types again, the restart cancels the
                // handler here and the backend is never called for the obsolete query.
                try await Task.sleep(for: .milliseconds(10))
                return try await backend.fetchResults(for: query)
            }])

            let response = try await Search.sendAndWaitForResponse(
                eventBus: eventBus,
                payload: "apple",
                timeout: .seconds(1)
            )
            #expect(response.busEvent.payload == ["result for apple"])
        }

        // MARK: - Internal coverage (not an example)

        // This is not a user-facing example. It is internal coverage that
        // .parallel actually executes invocations concurrently rather than
        // accidentally serializing them through some other point in the
        // EventBus pipeline. The .parallel example for users lives in
        // EventBusReadMeExampleTests.
        @Test
        func parallelHandlersExecuteConcurrently() async throws {
            @RequestResponseHandlerTypes
            enum LogPageView: RequestResponsePayloadHandler {
                typealias RequestPayload = String
                static let concurrencyType: EventBus.ConcurrencyType = .parallel
            }

            let eventBus = EventBus(defaultTimeout: .seconds(1))
            let (handlerEntered, entrySignal) = AsyncStream<String>.makeStream()
            let (releaseHandlers, releaseSignal) = AsyncStream<Void>.makeStream()

            eventBus.register(handlers: [LogPageView.handlerRegistration { screenName in
                entrySignal.yield(screenName)
                // Each invocation suspends here until the test releases all of them,
                // proving multiple invocations are simultaneously suspended.
                for await _ in releaseHandlers {
                    break
                }
            }])

            async let firstResponse = LogPageView.sendAndWaitForResponse(eventBus: eventBus, payload: "home")
            async let secondResponse = LogPageView.sendAndWaitForResponse(eventBus: eventBus, payload: "settings")

            var entries = handlerEntered.makeAsyncIterator()
            let first = await entries.next()
            let second = await entries.next()
            #expect(Set([first, second].compactMap(\.self)) == ["home", "settings"])

            releaseSignal.finish()
            _ = try await firstResponse
            _ = try await secondResponse
        }
    }
}
