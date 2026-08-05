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
import ConcurrencyExtras
import Foundation

// swiftformat:disable opaqueGenericParameters
extension EventBus {
    private typealias BridgingHandler<Payload> = @Sendable (Payload) async throws -> [AnyTrackedBusEventType?]?

    // MARK: - Parallel handlers

    func attachParallelTrackedBusEventHandler<EventType: Equatable & Sendable, Payload: Sendable>(
        _ eventToMatch: EventType,
        priority: TaskPriority? = nil,
        handler: @escaping TrackedBusEventHandler<EventType, Payload>
    ) -> AnyCancellable {
        subscription(to: eventToMatch)
            .sink { [weak self] typedTrackedEvent in
                Task(priority: priority) { [weak self] in
                    await self?.performCancellableOperation(
                        for: eventToMatch,
                        typedTrackedEvent: typedTrackedEvent
                    ) { eventBus, trackedEvent in
                        await eventBus.invokeTrackedBusEventHandler(with: trackedEvent) { _ in
                            try await handler(trackedEvent)
                        }
                    }
                }
            }
    }

    func attachParallelHandler<EventType: Equatable & Sendable, Payload: Sendable>(
        _ eventToMatch: EventType,
        priority: TaskPriority? = nil,
        handler: @escaping Handler<Payload>
    ) -> AnyCancellable {
        subscription(to: eventToMatch)
            .sink { [weak self] typedTrackedEvent in
                Task(priority: priority) { [weak self] in
                    await self?.performCancellableOperation(
                        for: eventToMatch,
                        typedTrackedEvent: typedTrackedEvent
                    ) { eventBus, trackedEvent in
                        let adaptedHandler: Handler<Payload> = { payload in
                            try await handler(payload)
                        }
                        await eventBus.invokePayloadHandler(with: trackedEvent, handler: adaptedHandler)
                    }
                }
            }
    }

    // MARK: - Serial handlers

    func attachSerialHandler<EventType: Equatable & Sendable, Payload: Sendable>(
        _ eventToMatch: EventType,
        priority: TaskPriority? = nil,
        handler: @escaping Handler<Payload>
    ) -> AnyCancellable {
        subscription(to: eventToMatch)
            .buffer(size: maxBufferSize, prefetch: .keepFull, whenFull: .dropNewest)
            .asyncMap(priority: priority) { [weak self] typedTrackedEvent in
                await self?.performCancellableOperation(
                    for: eventToMatch,
                    typedTrackedEvent: typedTrackedEvent
                ) { eventBus, trackedEvent in
                    let adaptedHandler: Handler<Payload> = { payload in
                        try await handler(payload)
                    }
                    await eventBus.invokePayloadHandler(with: trackedEvent, handler: adaptedHandler)
                }
            }
            .sink { _ in }
    }

    func attachSerialTrackedBusEventHandler<EventType: Equatable & Sendable, Payload: Sendable>(
        _ eventToMatch: EventType,
        priority: TaskPriority? = nil,
        handler: @escaping TrackedBusEventHandler<EventType, Payload>
    ) -> AnyCancellable {
        subscription(to: eventToMatch)
            .buffer(size: maxBufferSize, prefetch: .keepFull, whenFull: .dropNewest)
            .asyncMap(priority: priority) { [weak self] typedTrackedEvent in
                await self?.performCancellableOperation(
                    for: eventToMatch,
                    typedTrackedEvent: typedTrackedEvent
                ) { eventBus, trackedEvent in
                    await eventBus.invokeTrackedBusEventHandler(with: trackedEvent) { _ in
                        try await handler(trackedEvent)
                    }
                }
            }
            .sink { _ in }
    }

    private func performCancellableOperation<EventType: Equatable & Sendable, Payload: Sendable>(
        for eventToMatch: EventType,
        typedTrackedEvent: TrackedBusEvent<EventType, Payload>,
        operation: @escaping @Sendable (EventBus, TrackedBusEvent<EventType, Payload>) async -> Void
    ) async {
        let task = Task { [weak self] in
            guard let self else {
                return
            }
            await operation(self, typedTrackedEvent)
        }
        let handlerID = handlingInstances.addHandling(task: task, for: eventToMatch)
        await task.value
        handlingInstances.removeHandlingTask(with: handlerID)
    }

    func attachRestartTrackedBusEventHandler<EventType: Equatable & Sendable, Payload: Sendable>(
        _ eventToMatch: EventType,
        priority: TaskPriority? = nil,
        handler: @escaping EventBus.TrackedBusEventHandler<EventType, Payload>
    ) -> AnyCancellable {
        subscription(to: eventToMatch)
            .sink { [weak self] typedTrackedEvent in
                Task(priority: priority) { [weak self] in
                    await self?.performReplaceableTask(for: eventToMatch, priority: priority) { [weak self] in
                        await self?.invokeTrackedBusEventHandler(with: typedTrackedEvent) { _ in
                            try await handler(typedTrackedEvent)
                        }
                    }
                }
            }
    }

    func attachRestartHandler<EventType: Equatable & Sendable, Payload: Sendable>(
        _ eventToMatch: EventType,
        priority: TaskPriority? = nil,
        handler: @escaping EventBus.Handler<Payload>
    ) -> AnyCancellable {
        subscription(to: eventToMatch)
            .sink { [weak self] typedTrackedEvent in
                Task(priority: priority) { [weak self] in
                    await self?.performReplaceableTask(for: eventToMatch, priority: priority) { [weak self] in
                        let adaptedHandler: Handler<Payload> = { payload in
                            try await handler(payload)
                        }
                        await self?.invokePayloadHandler(with: typedTrackedEvent, handler: adaptedHandler)
                    }
                }
            }
    }

    private func subscription<EventType: Equatable & Sendable, Payload: Sendable>(
        to matchingEvent: EventType
    ) -> AnyPublisher<TrackedBusEvent<EventType, Payload>, Never> {
        subject
            .compactMap { [weak self] eventHistory -> TrackedBusEvent<EventType, Payload>? in
                guard let self else {
                    return nil
                }

                return eventHistory.matchAndTypeEvent(matchingEvent, self)
            }
            .eraseToAnyPublisher()
    }

    private func performReplaceableTask<EventType: Equatable & Sendable>(
        for event: EventType,
        priority: TaskPriority?,
        task: @escaping @Sendable () async -> Void
    ) async {
        let localTask = Task(priority: priority) { await task() }
        let handlerID = handlingInstances.replaceAllHandlingTasks(with: localTask, matching: event)
        await localTask.value
        handlingInstances.removeHandlingTask(with: handlerID)
    }

    private func invokePayloadHandler<EventType: Equatable & Sendable, Payload: Sendable>(
        with inputEvent: TrackedBusEvent<EventType, Payload>,
        handler: @escaping Handler<Payload>
    ) async {
        await invokeCommonHandler(with: inputEvent, handler: handler) { [weak self] events in
            self?.notifyPayloadHandlerObservers(about: events, with: inputEvent.eventHistory)
        }
    }

    private func invokeTrackedBusEventHandler<EventType: Equatable & Sendable, Payload: Sendable>(
        with inputEvent: TrackedBusEvent<EventType, Payload>,
        handler: @escaping BridgingHandler<Payload>
    ) async {
        await invokeCommonHandler(with: inputEvent, handler: handler) { [weak self] events in
            self?.notifyTrackedBusEventHandlerObservers(about: events)
        }
    }

    private func invokeCommonHandler<EventType: Equatable & Sendable, Payload: Sendable, Result>(
        with inputEvent: TrackedBusEvent<EventType, Payload>,
        handler: @escaping @Sendable (Payload) async throws -> [Result?]?,
        publish: @escaping @Sendable ([Result?]) -> Void
    ) async {
        do {
            eventBusLogger?.log(inputEvent.eventHistory, inputEvent.busEvent, as: .enteredHandler)
            let events = try await handler(inputEvent.busEvent.payload) ?? []
            eventBusLogger?.log(inputEvent.eventHistory, inputEvent.busEvent, as: .exitedHandler)
            publish(events)
        } catch {
            notifyErrorObservers(about: error, for: inputEvent)
        }
    }

    private func notifyPayloadHandlerObservers(
        about resultEvents: [AnyBusEventType?],
        with previousHistory: BusEventProcessRecord
    ) {
        notifyCommonObservers(about: resultEvents) { [weak self] event in
            guard let self else {
                return nil
            }
            let history = wrapWithPreviousProcessHistory(
                event: event,
                stepType: .handlerResult,
                historyProcessRecord: previousHistory
            )
            return ErasedTrackedBusEvent(eventHistory: history, busEvent: event)
        }.forEach {
            eventBusLogger?.log($0.eventHistory, $0.busEvent, as: .responded)
            subject.send($0.eventHistory)
        }
    }

    private func notifyTrackedBusEventHandlerObservers(
        about resultEvents: [AnyTrackedBusEventType?]
    ) {
        notifyCommonObservers(about: resultEvents) { [weak self] trackedEvent in
            guard self != nil else {
                return nil
            }
            return ErasedTrackedBusEvent(
                eventHistory: trackedEvent.eventHistory,
                busEvent: trackedEvent.busEvent
            )
        }.forEach {
            eventBusLogger?.log($0.eventHistory, $0.busEvent, as: .responded)
            subject.send($0.eventHistory)
        }
    }

    private func notifyCommonObservers<Input>(
        about resultEvents: [Input?],
        transform: (Input) -> ErasedTrackedBusEvent?
    ) -> [ErasedTrackedBusEvent] {
        resultEvents.compactMap { input in
            guard let input else {
                return nil
            }
            return transform(input)
        }
    }

    private func notifyErrorObservers<EventType: Equatable & Sendable, Payload: Sendable>(
        about error: Error,
        for typedTrackedEvent: TrackedBusEvent<EventType, Payload>
    ) {
        let inputEvent = typedTrackedEvent.busEvent
        let errorEvent = BusErrorEvent(eventType: inputEvent.eventType, payload: error)
        let newHistory = wrapWithPreviousProcessHistory(
            event: errorEvent,
            stepType: .handlerError,
            historyProcessRecord: typedTrackedEvent.eventHistory
        )
        subject.send(newHistory)
    }
}

// swiftformat:enable opaqueGenericParameters
