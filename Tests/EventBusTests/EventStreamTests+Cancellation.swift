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

@Suite("Cancellation Handler Tests")
struct CancellationHandlerTests {
    private enum Constants {
        static let defaultTimeout = Duration.seconds(1)
    }
}

// MARK: Serial Handler Tests

extension CancellationHandlerTests {
    @Test
    func serialTrackedHandlerCancelsByEventType() async throws {
        enum Handler: RequestResponseTrackedBusEventHandler {
            typealias RequestPayload = Duration
            typealias ResponsePayload = Duration
            static let concurrencyType: EventBus.ConcurrencyType = .serial
        }

        let testBus = EventBus(defaultTimeout: Constants.defaultTimeout)
        let wasCancelled = LockIsolated<Bool>(false)
        let (handlerEntered, entrySignal) = AsyncStream<Void>.makeStream()
        let (handlerExited, exitSignal) = AsyncStream<Void>.makeStream()

        testBus.register(handlers: [Handler.handlerRegistration { inputEvent in
            entrySignal.yield()
            defer { exitSignal.yield() }
            do {
                try await Task.sleep(for: inputEvent.busEvent.payload)
            } catch {
                if error is CancellationError {
                    wasCancelled.setValue(true)
                }
                throw error
            }

            return await inputEvent.appendEvent(
                Handler.response(payload: inputEvent.busEvent.payload)
            )
        }])

        var entries = handlerEntered.makeAsyncIterator()
        var exits = handlerExited.makeAsyncIterator()

        let response = try await Handler.sendAndWaitForResponse(
            eventBus: testBus,
            payload: .zero,
            timeout: .milliseconds(300)
        )
        _ = await entries.next()
        _ = await exits.next()

        #expect(response.busEvent.eventType == Handler.responseID)
        #expect(response.busEvent.payload == .zero)

        let sendError = LockIsolated<Error?>(nil)
        let sendTask = Task {
            do {
                _ = try await Handler.sendAndWaitForResponse(
                    eventBus: testBus,
                    payload: .seconds(5),
                    timeout: .seconds(1)
                )
                Issue.record("sendAndWait should have thrown after cancellation")
            } catch {
                sendError.setValue(error)
            }
        }

        _ = await entries.next()
        await testBus.cancelHandlers(for: Handler.requestID)
        _ = await exits.next()

        await sendTask.value
        #expect(sendError.value is CancellationError)
        #expect(wasCancelled.value)
    }

    @Test
    func serialTrackedSendAndWaitThrowsOnCancel() async {
        enum Handler: RequestResponseTrackedBusEventHandler {
            typealias RequestPayload = Duration
            static let concurrencyType: EventBus.ConcurrencyType = .serial
        }

        let testBus = EventBus(defaultTimeout: Constants.defaultTimeout)
        let (handlerEntered, entrySignal) = AsyncStream<Void>.makeStream()
        testBus.register(handlers: [Handler.handlerRegistration { inputEvent in
            entrySignal.yield()
            try await Task.sleep(for: inputEvent.busEvent.payload)
            return await inputEvent.appendEvent(Handler.response())
        }])

        let sendError = LockIsolated<Error?>(nil)
        let sendTask = Task {
            do {
                _ = try await Handler.sendAndWaitForResponse(
                    eventBus: testBus,
                    payload: .seconds(5),
                    timeout: .seconds(1)
                )
                Issue.record("sendAndWait should have thrown after cancellation")
            } catch {
                sendError.setValue(error)
            }
        }

        var entries = handlerEntered.makeAsyncIterator()
        _ = await entries.next()

        await testBus.cancelHandlers(for: Handler.requestID)

        await sendTask.value
        #expect(sendError.value is CancellationError)
    }

    @Test
    func serialHandlerCancelsByEventType() async {
        enum Handler: RequestResponsePayloadHandler {
            typealias RequestPayload = Duration
            static let concurrencyType: EventBus.ConcurrencyType = .serial
        }

        let testBus = EventBus(defaultTimeout: Constants.defaultTimeout)
        let wasCancelled = LockIsolated<Bool>(false)
        let wasCalled = LockIsolated<Bool>(false)
        let (handlerEntered, entrySignal) = AsyncStream<Void>.makeStream()
        let (handlerExited, exitSignal) = AsyncStream<Void>.makeStream()

        testBus.register(handlers: [Handler.handlerRegistration { sleepDuration in
            entrySignal.yield()
            do {
                try await Task.sleep(for: sleepDuration)
                wasCalled.setValue(true)
            } catch is CancellationError {
                wasCancelled.setValue(true)
            }
            exitSignal.yield()
        }])

        await Handler.send(eventBus: testBus, payload: .seconds(5))

        var entries = handlerEntered.makeAsyncIterator()
        _ = await entries.next()

        await testBus.cancelHandlers(for: Handler.requestID)

        var exits = handlerExited.makeAsyncIterator()
        _ = await exits.next()

        #expect(wasCancelled.value)
        #expect(!wasCalled.value)
    }

    @Test
    func serialSendAndWaitThrowsOnCancel() async {
        enum Handler: RequestResponsePayloadHandler {
            typealias RequestPayload = Duration
            static let concurrencyType: EventBus.ConcurrencyType = .serial
        }

        let testBus = EventBus(defaultTimeout: Constants.defaultTimeout)
        let (handlerEntered, entrySignal) = AsyncStream<Void>.makeStream()
        testBus.register(handlers: [Handler.handlerRegistration { sleepDuration in
            entrySignal.yield()
            try await Task.sleep(for: sleepDuration)
        }])

        let sendError = LockIsolated<Error?>(nil)
        let sendTask = Task {
            do {
                _ = try await Handler.sendAndWaitForResponse(
                    eventBus: testBus,
                    payload: .seconds(5),
                    timeout: .seconds(1)
                )
                Issue.record("sendAndWait should have thrown after cancellation")
            } catch {
                sendError.setValue(error)
            }
        }

        var entries = handlerEntered.makeAsyncIterator()
        _ = await entries.next()

        await testBus.cancelHandlers(for: Handler.requestID)

        await sendTask.value
        #expect(sendError.value is CancellationError)
    }
}

// MARK: Parallel Handler Tests

extension CancellationHandlerTests {
    @Test
    func parallelTrackedHandlerCancelsByEventType() async {
        enum Handler: RequestResponseTrackedBusEventHandler {
            typealias RequestPayload = Duration
        }

        let testBus = EventBus(defaultTimeout: Constants.defaultTimeout)
        let wasCancelled = LockIsolated<Bool>(false)
        let wasCalled = LockIsolated<Bool>(false)
        let (handlerEntered, entrySignal) = AsyncStream<Void>.makeStream()
        let (handlerExited, exitSignal) = AsyncStream<Void>.makeStream()

        testBus.register(handlers: [Handler.handlerRegistration { inputEvent in
            entrySignal.yield()
            do {
                try await Task.sleep(for: inputEvent.busEvent.payload)
                wasCalled.setValue(true)
            } catch is CancellationError {
                wasCancelled.setValue(true)
            }
            exitSignal.yield()
            return await inputEvent.appendEvent(Handler.response())
        }])

        await Handler.send(eventBus: testBus, payload: .seconds(5))

        var entries = handlerEntered.makeAsyncIterator()
        _ = await entries.next()

        await testBus.cancelHandlers(for: Handler.requestID)

        var exits = handlerExited.makeAsyncIterator()
        _ = await exits.next()

        #expect(wasCancelled.value)
        #expect(!wasCalled.value)
    }

    @Test
    func parallelTrackedSendAndWaitThrowsOnCancel() async {
        enum Handler: RequestResponseTrackedBusEventHandler {
            typealias RequestPayload = Duration
        }

        let testBus = EventBus(defaultTimeout: Constants.defaultTimeout)
        let (handlerEntered, entrySignal) = AsyncStream<Void>.makeStream()
        testBus.register(handlers: [Handler.handlerRegistration { inputEvent in
            entrySignal.yield()
            try await Task.sleep(for: inputEvent.busEvent.payload)
            return await inputEvent.appendEvent(Handler.response())
        }])

        let sendError = LockIsolated<Error?>(nil)
        let sendTask = Task {
            do {
                _ = try await Handler.sendAndWaitForResponse(
                    eventBus: testBus,
                    payload: .seconds(5),
                    timeout: .seconds(1)
                )
                Issue.record("sendAndWait should have thrown after cancellation")
            } catch {
                sendError.setValue(error)
            }
        }

        var entries = handlerEntered.makeAsyncIterator()
        _ = await entries.next()

        await testBus.cancelHandlers(for: Handler.requestID)

        await sendTask.value
        #expect(sendError.value is CancellationError)
    }

    @Test
    func parallelHandlerCancelsByEventType() async {
        enum Handler: RequestResponsePayloadHandler {
            typealias RequestPayload = Duration
        }

        let testBus = EventBus(defaultTimeout: Constants.defaultTimeout)
        let wasCancelled = LockIsolated<Bool>(false)
        let wasCalled = LockIsolated<Bool>(false)
        let (handlerEntered, entrySignal) = AsyncStream<Void>.makeStream()
        let (handlerExited, exitSignal) = AsyncStream<Void>.makeStream()

        testBus.register(handlers: [Handler.handlerRegistration { sleepDuration in
            entrySignal.yield()
            do {
                try await Task.sleep(for: sleepDuration)
                wasCalled.setValue(true)
            } catch is CancellationError {
                wasCancelled.setValue(true)
            }
            exitSignal.yield()
        }])

        await Handler.send(eventBus: testBus, payload: .seconds(5))

        var entries = handlerEntered.makeAsyncIterator()
        _ = await entries.next()

        await testBus.cancelHandlers(for: Handler.requestID)

        var exits = handlerExited.makeAsyncIterator()
        _ = await exits.next()

        #expect(wasCancelled.value)
        #expect(!wasCalled.value)
    }

    @Test
    func parallelSendAndWaitThrowsOnCancel() async {
        enum Handler: RequestResponsePayloadHandler {
            typealias RequestPayload = Duration
        }

        let testBus = EventBus(defaultTimeout: Constants.defaultTimeout)
        let (handlerEntered, entrySignal) = AsyncStream<Void>.makeStream()
        testBus.register(handlers: [Handler.handlerRegistration { sleepDuration in
            entrySignal.yield()
            try await Task.sleep(for: sleepDuration)
        }])

        let sendError = LockIsolated<Error?>(nil)
        let sendTask = Task {
            do {
                _ = try await Handler.sendAndWaitForResponse(
                    eventBus: testBus,
                    payload: .seconds(5),
                    timeout: .seconds(1)
                )
                Issue.record("sendAndWait should have thrown after cancellation")
            } catch {
                sendError.setValue(error)
            }
        }

        var entries = handlerEntered.makeAsyncIterator()
        _ = await entries.next()

        await testBus.cancelHandlers(for: Handler.requestID)

        await sendTask.value
        #expect(sendError.value is CancellationError)
    }
}
