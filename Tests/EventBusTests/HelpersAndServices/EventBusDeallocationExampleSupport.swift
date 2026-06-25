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

@testable import EventBus

actor DeallocPeriodicEventTimer {
    private var activeTask: Task<Void, Never>?
    private var startedRunCount = 0
    private var stoppedContinuation: CheckedContinuation<Void, Never>?

    func startIfNeeded(
        interval: Duration,
        maximumFireCount: Int,
        eventBus: @escaping @Sendable () -> (any EventBusCallback)?,
        sendPeriodicEvent: @escaping @Sendable (any EventBusCallback) async -> Void
    ) {
        guard activeTask == nil else {
            return
        }

        startedRunCount += 1
        activeTask = Task {
            await run(
                interval: interval,
                maximumFireCount: maximumFireCount,
                eventBus: eventBus,
                sendPeriodicEvent: sendPeriodicEvent
            )
        }
    }

    func waitUntilStopped() async {
        guard activeTask != nil else {
            return
        }

        await withCheckedContinuation { continuation in
            stoppedContinuation = continuation
        }
    }

    func runCount() -> Int {
        startedRunCount
    }

    private func run(
        interval: Duration,
        maximumFireCount: Int,
        eventBus: @escaping @Sendable () -> (any EventBusCallback)?,
        sendPeriodicEvent: @escaping @Sendable (any EventBusCallback) async -> Void
    ) async {
        for _ in 0 ..< maximumFireCount {
            guard eventBus() != nil else {
                break
            }

            do {
                try await Task.sleep(for: interval)
            } catch {
                break
            }

            guard let eventBus = eventBus() else {
                break
            }

            await sendPeriodicEvent(eventBus)
        }

        activeTask = nil
        stoppedContinuation?.resume()
        stoppedContinuation = nil
    }
}

protocol DeallocPeriodicColorServicing: Sendable {
    func nextColor() async -> String
    func waitUntilColorCount(_ expectedCount: Int) async
    func currentColorCount() async -> Int
}

actor DeallocPeriodicColorService: DeallocPeriodicColorServicing {
    private let expectedColor: String
    private var colorCount = 0
    private var colorCountContinuation: CheckedContinuation<Void, Never>?
    private var expectedColorCount = 0

    init(expectedColor: String) {
        self.expectedColor = expectedColor
    }

    func nextColor() async -> String {
        colorCount += 1
        resumeColorCountContinuationIfNeeded()
        return expectedColor
    }

    func waitUntilColorCount(_ expectedCount: Int) async {
        guard colorCount < expectedCount else {
            return
        }

        await withCheckedContinuation { continuation in
            expectedColorCount = expectedCount
            colorCountContinuation = continuation
        }
    }

    func currentColorCount() -> Int {
        colorCount
    }

    private func resumeColorCountContinuationIfNeeded() {
        guard colorCount >= expectedColorCount else {
            return
        }

        colorCountContinuation?.resume()
        colorCountContinuation = nil
    }
}

protocol DeallocLegacyColorCallbacks: Sendable {
    func colorDidChange() async -> String?
}

protocol DeallocLegacyColorServicing: Sendable {
    func installCallbacks(_ callbacks: any DeallocLegacyColorCallbacks) async
    func simulateColorCallback() async -> String?
    func nextColor() async -> String
    func currentColorCount() async -> Int
}

actor DeallocLegacyColorService: DeallocLegacyColorServicing {
    private let expectedColor: String
    private var callbacks: (any DeallocLegacyColorCallbacks)?
    private var colorCount = 0

    init(expectedColor: String) {
        self.expectedColor = expectedColor
    }

    func installCallbacks(_ callbacks: any DeallocLegacyColorCallbacks) async {
        self.callbacks = callbacks
    }

    func simulateColorCallback() async -> String? {
        await callbacks?.colorDidChange()
    }

    func nextColor() async -> String {
        colorCount += 1
        return expectedColor
    }

    func currentColorCount() -> Int {
        colorCount
    }
}
