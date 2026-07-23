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

/// Represents a matchable, customizable logging trigger for a specific event type and payload.
/// Allows per-event-type control over what log points are added.
public protocol LogPointable: Sendable, Hashable {
    associatedtype EventType: Equatable & Sendable
    associatedtype Payload: Sendable

    var logPointType: LogPointType { get }
    var eventType: EventType { get }
    var formatPayload: @Sendable (_ payload: Payload) -> (String) { get }

    func matches(logPointType: LogPointType) -> Bool
    func matches(eventType: Any) -> Bool
}

/// A strongly typed dictionary key for log point lookup.
public struct LogPointKey: Hashable, Sendable {
    let eventTypeIdentifier: String
    let logPointType: LogPointType

    public init(eventType: Any, logPointType: LogPointType) {
        eventTypeIdentifier = String(describing: eventType)
        self.logPointType = logPointType
    }
}

/// Concrete implementation of a LogPointable type.
/// Associates a set of LogPointTypes with a specific EventType/Payload.
public struct LogPoint<EventType: Equatable & Sendable, Payload: Sendable>: LogPointable {
    public let logPointType: LogPointType
    public let eventType: EventType
    public let formatPayload: @Sendable (_ payload: Payload) -> (String)

    public init(
        logPointType: LogPointType,
        eventType: EventType,
        formatPayload: @escaping @Sendable (_ payload: Payload) -> (String)
    ) {
        self.logPointType = logPointType
        self.eventType = eventType
        self.formatPayload = formatPayload
    }

    public func matches(logPointType: LogPointType) -> Bool {
        self.logPointType == logPointType
    }

    public func matches(eventType: Any) -> Bool {
        guard let casted = eventType as? EventType else {
            return false
        }
        return casted == self.eventType
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(logPointType)
        hasher.combine(String(describing: eventType))
    }

    // Manual equality ignoring formatPayload function because closures cannot be compared.
    public static func == (lhs: LogPoint<EventType, Payload>, rhs: LogPoint<EventType, Payload>) -> Bool {
        lhs.logPointType == rhs.logPointType &&
            lhs.eventType == rhs.eventType
    }
}

public enum LogPointType: Sendable, Hashable {
    case sent
    case responded
    case enteredHandler
    case exitedHandler
    case errored(Error)

    var description: String {
        switch self {
        case .sent: "Sent"
        case .responded: "Responded"
        case .enteredHandler: "Entered handler"
        case .exitedHandler: "Exited handler"
        case .errored: "Handler errored"
        }
    }

    var emoji: String {
        switch self {
        case .sent: "📤"
        case .responded: "📬"
        case .enteredHandler: "🔵"
        case .exitedHandler: "🟢"
        case .errored: "❌"
        }
    }

    public static func == (lhs: LogPointType, rhs: LogPointType) -> Bool {
        switch (lhs, rhs) {
        case (.enteredHandler, .enteredHandler),
             (.errored, .errored),
             (.exitedHandler, .exitedHandler),
             (.responded, .responded),
             (.sent, .sent):
            true
        default:
            false
        }
    }

    // swiftlint:disable no_magic_numbers
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .sent:
            hasher.combine(0)
        case .responded:
            hasher.combine(1)
        case .enteredHandler:
            hasher.combine(2)
        case .exitedHandler:
            hasher.combine(3)
        case .errored:
            hasher.combine(4)
        }
    }
    // swiftlint:enable no_magic_numbers
}

/// Type-erased wrapper for any LogPointable.
/// Allows storing heterogeneous log points in a Set without losing matching functionality.
public struct AnyLogPoint: Sendable, Hashable {
    public let base: any LogPointable
    private let box: any _AnyLogPointableBox

    public init(_ base: some LogPointable) {
        self.base = base
        box = _LogPointBox(base)
    }

    public func matches(_ eventType: Any, _ logPointType: LogPointType) -> Bool {
        base.matches(logPointType: logPointType) &&
            box.matches(eventType: eventType)
    }

    public static func == (lhs: AnyLogPoint, rhs: AnyLogPoint) -> Bool {
        lhs.box.isEqual(to: rhs.box)
    }

    public func hash(into hasher: inout Hasher) {
        box.hash(into: &hasher)
    }

    /// Attempts to format a payload using the underlying LogPointable's logic if possible.
    func formatPayloadIfPossible(payload: Any) -> String? {
        box.formatPayloadIfPossible(payload: payload)
    }
}

// swiftlint:disable type_name
/// protocol to abstract over type-specific behavior in AnyLogPoint.
/// Not for public use
protocol _AnyLogPointableBox: Sendable, Hashable {
    func isEqual(to other: any _AnyLogPointableBox) -> Bool
    func formatPayloadIfPossible(payload: Any) -> String?
    func matches(eventType: Any) -> Bool
}

/// Concrete box implementation for a specific LogPointable type.
/// Not for public use
struct _LogPointBox<Base: LogPointable>: _AnyLogPointableBox {
    let base: Base

    init(_ base: Base) {
        self.base = base
    }

    func hash(into hasher: inout Hasher) {
        base.hash(into: &hasher)
    }

    func isEqual(to other: any _AnyLogPointableBox) -> Bool {
        guard let otherBox = other as? _LogPointBox<Base> else {
            return false
        }
        return base == otherBox.base
    }

    func formatPayloadIfPossible(payload: Any) -> String? {
        guard let typedPayload = payload as? Base.Payload else {
            return nil
        }
        return base.formatPayload(typedPayload)
    }

    func matches(eventType: Any) -> Bool {
        base.matches(eventType: eventType)
    }

    static func == (lhs: _LogPointBox<Base>, rhs: _LogPointBox<Base>) -> Bool {
        lhs.base == rhs.base
    }
}

// swiftlint:enable type_name
