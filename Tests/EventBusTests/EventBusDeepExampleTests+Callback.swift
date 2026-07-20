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
import Foundation
import Testing

// swiftlint:disable nesting
extension EventBusDeepExampleTests {
    @Suite("EventBus callback examples")
    struct EventBusDeepExampleTestsCallback {
        private enum Constants {
            static let expectedColor = "Green"
            static let minimumPeriodicColorCount = 2
            static let periodicTimerInterval: Duration = .milliseconds(minimumPeriodicColorCount)
            static let periodicTimerMaximumFireCount = 5
            static let serviceCallbackExpectedColorCount = 1
            static let timeoutMilliseconds = 300
        }

        @Test
        func weakEventBusTimerExample() async throws {
            struct PeriodicColorHandler: Sendable {
                @RequestResponseHandlerTypes
                enum StartPeriodicColors: RequestResponseTrackedBusEventHandler {}

                @RequestResponseHandlerTypes
                enum GetPeriodicColor: RequestResponsePayloadHandler {
                    typealias ResponsePayload = String
                }

                private let colorService: DeallocPeriodicColorServicing
                private let timer: DeallocPeriodicEventTimer

                init(
                    colorService: DeallocPeriodicColorServicing,
                    timer: DeallocPeriodicEventTimer
                ) {
                    self.colorService = colorService
                    self.timer = timer
                }

                var handlers: [any Handlable] {
                    [
                        StartPeriodicColors.handlerRegistration { inputEvent in
                            await timer.startIfNeeded(
                                interval: Constants.periodicTimerInterval,
                                maximumFireCount: Constants.periodicTimerMaximumFireCount,
                                eventBus: { inputEvent.eventBusCallback },
                                sendPeriodicEvent: { eventBus in
                                    await eventBus.send(GetPeriodicColor.request())
                                }
                            )

                            return await inputEvent.appendEvent(StartPeriodicColors.response())
                        },
                        GetPeriodicColor.handlerRegistration {
                            await colorService.nextColor()
                        },
                    ]
                }
            }

            let colorService = DeallocPeriodicColorService(expectedColor: Constants.expectedColor)
            let timer = DeallocPeriodicEventTimer()
            let periodicColorHandler = PeriodicColorHandler(colorService: colorService, timer: timer)
            var eventBus: EventBus? = EventBus(defaultTimeout: .milliseconds(Constants.timeoutMilliseconds))
            weak var weakEventBus = eventBus
            eventBus?.register(handlers: periodicColorHandler.handlers)

            if let eventBus {
                _ = try await PeriodicColorHandler.StartPeriodicColors.sendAndWaitForResponse(
                    eventBus: eventBus,
                    timeout: .milliseconds(Constants.timeoutMilliseconds)
                )
                _ = try await PeriodicColorHandler.StartPeriodicColors.sendAndWaitForResponse(
                    eventBus: eventBus,
                    timeout: .milliseconds(Constants.timeoutMilliseconds)
                )
            } else {
                Issue.record("Expected EventBus to exist before sending event")
                return
            }

            #expect(await timer.runCount() == 1)
            await colorService.waitUntilColorCount(Constants.minimumPeriodicColorCount)

            eventBus = nil
            await timer.waitUntilStopped()

            let colorCount = await colorService.currentColorCount()
            #expect(colorCount >= Constants.minimumPeriodicColorCount)
            #expect(colorCount < Constants.periodicTimerMaximumFireCount)
            #expect(weakEventBus == nil)
        }

        @Test
        func weakEventBusServiceCallbackExample() async throws {
            struct LegacyColorHandler: Sendable {
                @RequestResponseHandlerTypes
                enum InstallCallbacks: RequestResponseTrackedBusEventHandler {}

                @RequestResponseHandlerTypes
                enum ColorChanged: RequestResponsePayloadHandler {
                    typealias ResponsePayload = String
                }

                actor EventBusCallbacks: DeallocLegacyColorCallbacks {
                    private weak var eventBus: EventBus?

                    init(eventBus: (any EventBusCallback)?) {
                        self.eventBus = eventBus as? EventBus
                    }

                    func colorDidChange() async -> String? {
                        guard let eventBus else {
                            return nil
                        }

                        do {
                            let response = try await ColorChanged.sendAndWaitForResponse(
                                eventBus: eventBus,
                                timeout: .milliseconds(Constants.timeoutMilliseconds)
                            )
                            return response.busEvent.payload
                        } catch {
                            return nil
                        }
                    }
                }

                private let colorService: DeallocLegacyColorServicing

                init(colorService: DeallocLegacyColorServicing) {
                    self.colorService = colorService
                }

                var handlers: [any Handlable] {
                    [
                        InstallCallbacks.handlerRegistration { inputEvent in
                            await colorService.installCallbacks(
                                EventBusCallbacks(eventBus: inputEvent.eventBusCallback)
                            )

                            return await inputEvent.appendEvent(InstallCallbacks.response())
                        },
                        ColorChanged.handlerRegistration {
                            await colorService.nextColor()
                        },
                    ]
                }
            }

            let colorService = DeallocLegacyColorService(expectedColor: Constants.expectedColor)
            let legacyColorHandler = LegacyColorHandler(colorService: colorService)
            var eventBus: EventBus? = EventBus(defaultTimeout: .milliseconds(Constants.timeoutMilliseconds))
            weak var weakEventBus = eventBus
            eventBus?.register(handlers: legacyColorHandler.handlers)

            if let eventBus {
                _ = try await LegacyColorHandler.InstallCallbacks.sendAndWaitForResponse(
                    eventBus: eventBus,
                    timeout: .milliseconds(Constants.timeoutMilliseconds)
                )
            } else {
                Issue.record("Expected EventBus to exist before sending event")
                return
            }

            let callbackColor = await colorService.simulateColorCallback()
            #expect(callbackColor == Constants.expectedColor)
            #expect(await colorService.currentColorCount() == Constants.serviceCallbackExpectedColorCount)

            eventBus = nil
            #expect(weakEventBus == nil)

            let callbackColorAfterDeallocation = await colorService.simulateColorCallback()
            #expect(callbackColorAfterDeallocation == nil)
            #expect(await colorService.currentColorCount() == Constants.serviceCallbackExpectedColorCount)
        }
    }
}

// swiftlint:enable nesting
