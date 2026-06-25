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

/// Base protocol for generic BusEvent primitives
public protocol BusEventType<EventType, Payload>: Sendable {
    associatedtype EventType: Equatable & Sendable
    associatedtype Payload: Sendable

    var eventType: EventType { get }
    var payload: Payload { get }
    /// Note the debugName should be the reflected/qualified name of the `EventType`, not the full generic name of the `BusEvent`, which is too chatty
    /// To achieve this, override `debugName` with `String(reflecting:` at the protocol that users are going to directly extend, or close to it,
    /// ..so the actual concrete type name is captured rather than the protocol's generic type.
    /// See `SimpleBusEventType` where the `debugName` is used directly and in associated types, but is overridden in `RequestResponseEventHandler`
    var debugName: String? { get }
}

public extension BusEventType {
    var debugName: String? { nil }
}

/// Used to type-erase BusEvent primitives
public typealias AnyBusEventType = any BusEventType

/// Primitive base generic for declaring bus events.
/// Best used internally to create new event interaction paradigms. See ``SimpleBusEventType``.
public struct BusEvent<EventType: Equatable & Sendable, Payload: Sendable>: BusEventType {
    public let eventType: EventType
    public let payload: Payload
    public let debugName: String?
    public init(eventType: EventType, payload: Payload, debugName: String? = nil) {
        self.eventType = eventType
        self.payload = payload
        self.debugName = debugName
    }
}

/// Holds an error to be thrown across the EventBus from a handler function to its caller if called with sendAndWait
public typealias BusErrorEvent<EventType: Equatable & Sendable> = BusEvent<EventType, Error>
