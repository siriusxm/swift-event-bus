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

@preconcurrency import Combine
import ConcurrencyExtras
import Foundation

/// Public access for EventBus - client objects instantiate and use this class directly. Registered bus handler functions access  EventBusCallback protocol.
/// EventBus is thread-safe and Sendable. See README for user guide.
public final class EventBus: Sendable {
    // Note: EventBus is deliberately declared as a class. This enables weak references to EventBus instances
    // ..and allows granular concurrency management of isolated internal elements, as well as synchronous setup

    public typealias TrackedBusEventHandler<E: Equatable, P> = @Sendable (TrackedBusEvent<E, P>) async throws -> [AnyTrackedBusEventType?]?
    public typealias Handler<P> = @Sendable (P) async throws -> [any BusEventType]?

    /// Execution modes for handlers
    ///
    /// - **serial**: This type of execution will run a handler instance right after the previous instance finishes. Only
    /// one instance runs at a time.
    /// - **parallel**: This type of execution will run any number of handler instances in parallel.
    /// Several instances run at the same time.
    /// - **restart**: This type of execution will cancel a running handler instance before running a new instance.
    /// Only one instance runs at a time.
    public enum ConcurrencyType: Sendable {
        case serial
        case parallel
        case restart
    }

    // As a successful "never timeout" value, ten years works.
    // UInt64.max stalls out Task.sleep, so using this smaller value
    static let tenYearsInSeconds: Int64 = 315_576_000
    public static let defaultThirtySecondsValue: Int64 = 30
    public static let maxTimeout = Duration.seconds(tenYearsInSeconds)
    public let defaultTimeout: Duration
    let maxBufferSize = 1024

    let currentEventSequenceValue = LockIsolated<EventSequenceIndex>(0)
    let eventBusLogger: EventBusLoggable?
    let handlerManager = EventBusHandlerManager()
    let handlingInstances = EventBusHandlingInstancesStorage()
    let subject: PassthroughSubject<BusEventProcessRecord, Never> = .init()

    public init(
        eventBusLogger: EventBusLoggable? = nil,
        defaultTimeout: Duration = .seconds(EventBus.defaultThirtySecondsValue)
    ) {
        self.eventBusLogger = eventBusLogger
        self.defaultTimeout = defaultTimeout
    }
}
