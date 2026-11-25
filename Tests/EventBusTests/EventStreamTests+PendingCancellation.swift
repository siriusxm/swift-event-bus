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

private enum PendingCancellationConstants {
    static let defaultTimeout = Duration.seconds(1)
    static let longHandlerDuration = Duration.seconds(EventBus.defaultThirtySecondsValue)
    static let activePayload = 0
    static let firstQueuedPayload = 1
    static let secondQueuedPayload = 2
    static let postCancellationPayload = 3
    static let massCancellationEventCount = 100
}

private extension Result where Success == Void, Failure == Error {
    var isCancellation: Bool {
        guard case let .failure(error) = self else {
            return false
        }
        return error is CancellationError
    }
}

// MARK: Pending Serial Handler Cancellation Tests

extension CancellationHandlerTests {
    @Test
    func serialPayloadHandlerSkipsQueuedEventsAfterCancellation() async throws {
        enum Handler: RequestResponsePayloadHandler {
            typealias RequestPayload = Int
            static let concurrencyType: EventBus.ConcurrencyType = .serial
        }

        let testBus = EventBus(defaultTimeout: PendingCancellationConstants.defaultTimeout)
        let enteredPayloads = LockIsolated<[Int]>([])
        let (handlerEntered, entrySignal) = AsyncStream<Int>.makeStream()
        let (handlerCompleted, completionSignal) = AsyncStream<Int>.makeStream()

        testBus.register(handlers: [Handler.handlerRegistration { payload in
            enteredPayloads.withValue { $0.append(payload) }
            entrySignal.yield(payload)
            if payload == PendingCancellationConstants.activePayload {
                try await Task.sleep(for: PendingCancellationConstants.longHandlerDuration)
            }
            completionSignal.yield(payload)
        }])

        var entries = handlerEntered.makeAsyncIterator()
        await Handler.send(eventBus: testBus, payload: PendingCancellationConstants.activePayload)
        #expect(await entries.next() == PendingCancellationConstants.activePayload)

        await Handler.send(eventBus: testBus, payload: PendingCancellationConstants.firstQueuedPayload)
        await Handler.send(eventBus: testBus, payload: PendingCancellationConstants.secondQueuedPayload)
        await testBus.cancelHandlers(for: Handler.requestID)
        await Handler.send(eventBus: testBus, payload: PendingCancellationConstants.postCancellationPayload)

        try await Task<Void, Error>(maximumDuration: PendingCancellationConstants.defaultTimeout) {
            var completions = handlerCompleted.makeAsyncIterator()
            while let payload = await completions.next() {
                if payload == PendingCancellationConstants.postCancellationPayload {
                    return
                }
            }
        }.value

        #expect(enteredPayloads.value == [PendingCancellationConstants.activePayload, PendingCancellationConstants.postCancellationPayload])
    }

    @Test
    func serialTrackedHandlerSkipsQueuedEventsAfterCancellation() async throws {
        enum Handler: RequestResponseTrackedBusEventHandler {
            typealias RequestPayload = Int
            typealias ResponsePayload = Int
            static let concurrencyType: EventBus.ConcurrencyType = .serial
        }

        let testBus = EventBus(defaultTimeout: PendingCancellationConstants.defaultTimeout)
        let enteredPayloads = LockIsolated<[Int]>([])
        let (handlerEntered, entrySignal) = AsyncStream<Int>.makeStream()
        let (handlerCompleted, completionSignal) = AsyncStream<Int>.makeStream()

        testBus.register(handlers: [Handler.handlerRegistration { inputEvent in
            let payload = inputEvent.busEvent.payload
            enteredPayloads.withValue { $0.append(payload) }
            entrySignal.yield(payload)
            if payload == PendingCancellationConstants.activePayload {
                try await Task.sleep(for: PendingCancellationConstants.longHandlerDuration)
            }
            completionSignal.yield(payload)
            return await inputEvent.appendEvent(Handler.response(payload: payload))
        }])

        var entries = handlerEntered.makeAsyncIterator()
        await Handler.send(eventBus: testBus, payload: PendingCancellationConstants.activePayload)
        #expect(await entries.next() == PendingCancellationConstants.activePayload)

        await Handler.send(eventBus: testBus, payload: PendingCancellationConstants.firstQueuedPayload)
        await Handler.send(eventBus: testBus, payload: PendingCancellationConstants.secondQueuedPayload)
        await testBus.cancelHandlers(for: Handler.requestID)
        await Handler.send(eventBus: testBus, payload: PendingCancellationConstants.postCancellationPayload)

        try await Task<Void, Error>(maximumDuration: PendingCancellationConstants.defaultTimeout) {
            var completions = handlerCompleted.makeAsyncIterator()
            while let payload = await completions.next() {
                if payload == PendingCancellationConstants.postCancellationPayload {
                    return
                }
            }
        }.value

        #expect(enteredPayloads.value == [PendingCancellationConstants.activePayload, PendingCancellationConstants.postCancellationPayload])
    }

    @Test
    func serialQueuedSendAndWaitCallsThrowCancellationError() async throws {
        enum Handler: RequestResponsePayloadHandler {
            typealias RequestPayload = Int
            typealias ResponsePayload = Int
            static let concurrencyType: EventBus.ConcurrencyType = .serial
        }

        let testBus = EventBus(defaultTimeout: PendingCancellationConstants.defaultTimeout)
        let enteredPayloads = LockIsolated<[Int]>([])
        let (handlerEntered, entrySignal) = AsyncStream<Int>.makeStream()
        let sentEvents = testBus.subject.bufferedValues
        var sentEventIterator = sentEvents.makeAsyncIterator()

        testBus.register(handlers: [Handler.handlerRegistration { payload in
            enteredPayloads.withValue { $0.append(payload) }
            entrySignal.yield(payload)
            if payload == PendingCancellationConstants.activePayload {
                try await Task.sleep(for: PendingCancellationConstants.longHandlerDuration)
            }
            return payload
        }])

        var entries = handlerEntered.makeAsyncIterator()
        let inFlightTask = Task<Result<Void, Error>, Never> {
            do {
                _ = try await Handler.sendAndWaitForResponse(eventBus: testBus, payload: PendingCancellationConstants.activePayload)
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        let inFlightEventRecord = try await sentEventIterator.next()
        #expect((inFlightEventRecord?.busEvent as? Handler.Request)?.payload == PendingCancellationConstants.activePayload)
        #expect(await entries.next() == PendingCancellationConstants.activePayload)

        let firstQueuedTask = Task<Result<Void, Error>, Never> {
            do {
                _ = try await Handler.sendAndWaitForResponse(eventBus: testBus, payload: PendingCancellationConstants.firstQueuedPayload)
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        let secondQueuedTask = Task<Result<Void, Error>, Never> {
            do {
                _ = try await Handler.sendAndWaitForResponse(eventBus: testBus, payload: PendingCancellationConstants.secondQueuedPayload)
                return .success(())
            } catch {
                return .failure(error)
            }
        }

        let firstQueuedEventRecord = try await sentEventIterator.next()
        let secondQueuedEventRecord = try await sentEventIterator.next()
        let queuedPayloads = [firstQueuedEventRecord, secondQueuedEventRecord].compactMap {
            ($0?.busEvent as? Handler.Request)?.payload
        }
        #expect(Set(queuedPayloads) == Set([PendingCancellationConstants.firstQueuedPayload, PendingCancellationConstants.secondQueuedPayload]))

        await testBus.cancelHandlers(for: Handler.requestID)
        let postCancellationResponse = try await Handler.sendAndWaitForResponse(
            eventBus: testBus,
            payload: PendingCancellationConstants.postCancellationPayload
        )

        let inFlightTaskResult = await inFlightTask.value
        let firstQueuedTaskResult = await firstQueuedTask.value
        let secondQueuedTaskResult = await secondQueuedTask.value

        #expect(inFlightTaskResult.isCancellation)
        #expect(firstQueuedTaskResult.isCancellation)
        #expect(secondQueuedTaskResult.isCancellation)
        #expect(postCancellationResponse.busEvent.payload == PendingCancellationConstants.postCancellationPayload)
        #expect(enteredPayloads.value == [PendingCancellationConstants.activePayload, PendingCancellationConstants.postCancellationPayload])
    }

    @Test
    func serialTrackedQueuedSendAndWaitThrowsCancellationError() async throws {
        enum Handler: RequestResponseTrackedBusEventHandler {
            typealias RequestPayload = Int
            typealias ResponsePayload = Int
            static let concurrencyType: EventBus.ConcurrencyType = .serial
        }

        let testBus = EventBus(defaultTimeout: PendingCancellationConstants.defaultTimeout)
        let enteredPayloads = LockIsolated<[Int]>([])
        let (handlerEntered, entrySignal) = AsyncStream<Int>.makeStream()
        let sentEvents = testBus.subject.bufferedValues
        var sentEventIterator = sentEvents.makeAsyncIterator()

        testBus.register(handlers: [Handler.handlerRegistration { inputEvent in
            let payload = inputEvent.busEvent.payload
            enteredPayloads.withValue { $0.append(payload) }
            entrySignal.yield(payload)
            if payload == PendingCancellationConstants.activePayload {
                try await Task.sleep(for: PendingCancellationConstants.longHandlerDuration)
            }
            return await inputEvent.appendEvent(Handler.response(payload: payload))
        }])

        var entries = handlerEntered.makeAsyncIterator()
        let inFlightTask = Task<Result<Void, Error>, Never> {
            do {
                _ = try await Handler.sendAndWaitForResponse(eventBus: testBus, payload: PendingCancellationConstants.activePayload)
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        let inFlightEventRecord = try await sentEventIterator.next()
        #expect((inFlightEventRecord?.busEvent as? Handler.Request)?.payload == PendingCancellationConstants.activePayload)
        #expect(await entries.next() == PendingCancellationConstants.activePayload)

        let queuedTask = Task<Result<Void, Error>, Never> {
            do {
                _ = try await Handler.sendAndWaitForResponse(eventBus: testBus, payload: PendingCancellationConstants.firstQueuedPayload)
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        let queuedEventRecord = try await sentEventIterator.next()
        #expect((queuedEventRecord?.busEvent as? Handler.Request)?.payload == PendingCancellationConstants.firstQueuedPayload)

        await testBus.cancelHandlers(for: Handler.requestID)
        let postCancellationResponse = try await Handler.sendAndWaitForResponse(
            eventBus: testBus,
            payload: PendingCancellationConstants.postCancellationPayload
        )

        let inFlightTaskResult = await inFlightTask.value
        let queuedTaskResult = await queuedTask.value

        #expect(inFlightTaskResult.isCancellation)
        #expect(queuedTaskResult.isCancellation)
        #expect(postCancellationResponse.busEvent.payload == PendingCancellationConstants.postCancellationPayload)
        #expect(enteredPayloads.value == [PendingCancellationConstants.activePayload, PendingCancellationConstants.postCancellationPayload])
    }

    @Test
    func serialMassCancellationSkipsAllQueuedEvents() async throws {
        enum Handler: RequestResponsePayloadHandler {
            typealias RequestPayload = Int
            typealias ResponsePayload = Int
            static let concurrencyType: EventBus.ConcurrencyType = .serial
        }

        let testBus = EventBus()
        let enteredPayloads = LockIsolated<[Int]>([])
        let (handlerEntered, entrySignal) = AsyncStream<Int>.makeStream()

        testBus.register(handlers: [Handler.handlerRegistration { payload in
            enteredPayloads.withValue { $0.append(payload) }
            entrySignal.yield(payload)
            if payload == PendingCancellationConstants.activePayload {
                try await Task.sleep(for: PendingCancellationConstants.longHandlerDuration)
            }
            return payload
        }])

        var entries = handlerEntered.makeAsyncIterator()
        await Handler.send(eventBus: testBus, payload: PendingCancellationConstants.activePayload)
        #expect(await entries.next() == PendingCancellationConstants.activePayload)

        let sentEvents = testBus.subject.bufferedValues
        var sentEventIterator = sentEvents.makeAsyncIterator()
        let queuedPayloads = PendingCancellationConstants.firstQueuedPayload ... PendingCancellationConstants.massCancellationEventCount
        let queuedTasks = queuedPayloads.map { payload in
            Task<Result<Void, Error>, Never> {
                do {
                    _ = try await Handler.sendAndWaitForResponse(eventBus: testBus, payload: payload)
                    return .success(())
                } catch {
                    return .failure(error)
                }
            }
        }

        var observedQueuedPayloads = Set<Int>()
        for _ in queuedPayloads {
            let eventRecord = try await sentEventIterator.next()
            if let payload = (eventRecord?.busEvent as? Handler.Request)?.payload {
                observedQueuedPayloads.insert(payload)
            }
        }
        #expect(observedQueuedPayloads == Set(queuedPayloads))

        await testBus.cancelHandlers(for: Handler.requestID)

        for queuedTask in queuedTasks {
            #expect((await queuedTask.value).isCancellation)
        }
        #expect(enteredPayloads.value == [PendingCancellationConstants.activePayload])
    }

    @Test
    func serialCancellationDoesNotAffectAnotherEventType() async throws {
        enum CancelledHandler: RequestResponsePayloadHandler {
            static let concurrencyType: EventBus.ConcurrencyType = .serial
        }
        enum UnaffectedHandler: RequestResponsePayloadHandler {
            typealias RequestPayload = Int
            typealias ResponsePayload = Int
            static let concurrencyType: EventBus.ConcurrencyType = .serial
        }

        let testBus = EventBus(defaultTimeout: PendingCancellationConstants.defaultTimeout)
        let (cancelledHandlerEntered, cancelledEntrySignal) = AsyncStream<Void>.makeStream()
        let (unaffectedHandlerEntered, unaffectedEntrySignal) = AsyncStream<Void>.makeStream()
        let (releaseUnaffectedHandler, unaffectedReleaseSignal) = AsyncStream<Void>.makeStream()

        testBus.register(handlers: [
            CancelledHandler.handlerRegistration {
                cancelledEntrySignal.yield()
                try await Task.sleep(for: PendingCancellationConstants.longHandlerDuration)
            },
            UnaffectedHandler.handlerRegistration { payload in
                unaffectedEntrySignal.yield()
                for await _ in releaseUnaffectedHandler {
                    break
                }
                try Task.checkCancellation()
                return payload
            },
        ])

        let cancelledError = LockIsolated<Error?>(nil)
        var cancelledEntries = cancelledHandlerEntered.makeAsyncIterator()
        let cancelledTask = Task {
            do {
                _ = try await CancelledHandler.sendAndWaitForResponse(eventBus: testBus)
            } catch {
                cancelledError.setValue(error)
            }
        }
        _ = await cancelledEntries.next()

        var unaffectedEntries = unaffectedHandlerEntered.makeAsyncIterator()
        let unaffectedTask = Task {
            try await UnaffectedHandler.sendAndWaitForResponse(
                eventBus: testBus,
                payload: PendingCancellationConstants.postCancellationPayload
            )
        }
        _ = await unaffectedEntries.next()

        await testBus.cancelHandlers(for: CancelledHandler.requestID)
        unaffectedReleaseSignal.finish()

        let unaffectedResponse = try await unaffectedTask.value
        await cancelledTask.value
        #expect(unaffectedResponse.busEvent.payload == PendingCancellationConstants.postCancellationPayload)
        #expect(cancelledError.value is CancellationError)
    }
}
