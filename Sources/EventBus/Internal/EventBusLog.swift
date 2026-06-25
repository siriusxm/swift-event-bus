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

import os

/// Lightweight logging shim backed by the unified logging system (`os.Logger`).
///
/// Replaces the former external logging dependency. The `tag` is prefixed onto
/// each message so logs can be filtered and searched the same way as before.
struct EventBusLog: Sendable {
    private let backing = Logger(subsystem: Constants.subsystem, category: Constants.category)

    private enum Constants {
        static let subsystem = "com.siriusxm.eventbus"
        static let category = "EventBus"
    }

    func info(_ message: String, tag: String) {
        backing.info("[\(tag, privacy: .public)] \(message, privacy: .public)")
    }

    func warning(_ message: String, tag: String) {
        backing.warning("[\(tag, privacy: .public)] \(message, privacy: .public)")
    }

    func debug(_ message: String, tag: String) {
        backing.debug("[\(tag, privacy: .public)] \(message, privacy: .public)")
    }
}

/// Shared EventBus logger instance, internal to the module.
let logger = EventBusLog()
