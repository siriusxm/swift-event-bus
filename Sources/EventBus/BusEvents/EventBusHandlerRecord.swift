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
import Foundation

public typealias AnyBusEventPublisher = any Publisher<any BusEventType, Never>
public typealias AnyEventType = any Equatable & Sendable

public typealias EventBusHandlerID = UUID
public typealias ServiceName = String

// Used internally for cancelling BusEvent handling instances
struct EventBusHandlerRecord: Sendable {
    let cancellable: AnyCancellable
    let eventType: AnyEventType
    let handlerID: EventBusHandlerID
    let serviceName: ServiceName
}
