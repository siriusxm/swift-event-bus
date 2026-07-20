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

/// Adds `TrackedEvent` to a `SimpleBusEventType` declaration so its tracked event can be named and extended.
@attached(member, names: named(TrackedEvent))
public macro SimpleBusEventTypes() = #externalMacro(module: "EventBusMacros", type: "SimpleBusEventTypesMacro")

/// Adds `TrackedEvent` plus typed `event` and `send` conveniences for a structured payload.
///
/// Each parameter must match, in declaration order, a parameter label from an initializer marked with
/// ``BusEventPayloadInit()``. Pass every listed parameter when calling generated conveniences, including
/// parameters whose payload initializer has a default value.
@attached(member, names: named(TrackedEvent), named(event), named(send))
public macro SimpleBusEventPayloadAndTypes(_ parameters: String...) = #externalMacro(
    module: "EventBusMacros",
    type: "SimpleBusEventPayloadAndTypesMacro"
)

/// Exposes a payload initializer to the `*PayloadAndTypes` macros.
///
/// Apply this macro to one non-async, non-throwing, non-failable initializer without variadic parameters.
/// Unlabeled, separately named, and escaped-keyword parameters are supported.
@attached(peer, names: arbitrary, named(_eventBusPayloadInit))
public macro BusEventPayloadInit() = #externalMacro(module: "EventBusMacros", type: "BusEventPayloadInitMacro")

/// Adds tracked aliases and typed trigger/response conveniences to a response handler.
///
/// Names in `triggerEvent` and `response` must match, in declaration order, initializer labels exposed by
/// ``BusEventPayloadInit()`` on the corresponding payload type. Empty arrays generate aliases only.
@attached(member, names: named(TrackedTriggerEvent), named(TrackedResponse), named(event), named(sendAndWaitForResponse), named(response))
public macro ResponseHandlerPayloadAndTypes(triggerEvent: [String] = [], response: [String] = []) = #externalMacro(
    module: "EventBusMacros",
    type: "ResponseHandlerPayloadAndTypesMacro"
)

/// Adds `TrackedTriggerEvent` and `TrackedResponse` aliases to a response handler declaration.
@attached(member, names: named(TrackedTriggerEvent), named(TrackedResponse))
public macro ResponseHandlerTypes() = #externalMacro(module: "EventBusMacros", type: "ResponseHandlerTypesMacro")

/// Adds tracked aliases and typed request/response conveniences to a request-response handler.
///
/// Names in `request` and `response` must match, in declaration order, initializer labels exposed by
/// ``BusEventPayloadInit()`` on the corresponding payload type. Empty arrays generate aliases only.
@attached(member, names: named(TrackedRequest), named(TrackedResponse), named(request), named(send), named(sendAndWaitForResponse), named(response))
public macro RequestResponseHandlerPayloadAndTypes(request: [String] = [], response: [String] = []) = #externalMacro(
    module: "EventBusMacros",
    type: "RequestResponseHandlerPayloadAndTypesMacro"
)

/// Adds `TrackedRequest` and `TrackedResponse` aliases to a request-response handler declaration.
@attached(member, names: named(TrackedRequest), named(TrackedResponse))
public macro RequestResponseHandlerTypes() = #externalMacro(module: "EventBusMacros", type: "RequestResponseHandlerTypesMacro")

/// Adds `TrackedTriggerEvent` and `TrackedResponse` aliases to a linked-event handler declaration.
@attached(member, names: named(TrackedTriggerEvent), named(TrackedResponse))
public macro LinkedEventHandlerTypes() = #externalMacro(module: "EventBusMacros", type: "LinkedEventHandlerTypesMacro")

/// Adds tracked aliases and typed trigger/response conveniences to a linked-event handler.
///
/// Names in `triggerEvent` and `response` must match, in declaration order, initializer labels exposed by
/// ``BusEventPayloadInit()`` on the corresponding payload type. Empty arrays generate aliases only.
@attached(member, names: named(TrackedTriggerEvent), named(TrackedResponse), named(event), named(sendAndWaitForResponse), named(response))
public macro LinkedEventHandlerPayloadAndTypes(triggerEvent: [String] = [], response: [String] = []) = #externalMacro(
    module: "EventBusMacros",
    type: "LinkedEventHandlerPayloadAndTypesMacro"
)
