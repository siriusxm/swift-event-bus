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
    @Suite("EventBus deallocation examples")
    struct EventBusDeepExampleTestsDeallocation {
        private enum Constants {
            static let expectedColor = "Green"
            static let timeoutMilliseconds = 300
        }

        @Test
        func singleServiceHandlerDeallocationExample() async throws {
            protocol ColorServiceProtocol: Sendable {
                func nextColor() async -> String
            }

            actor ColorService: ColorServiceProtocol {
                private let serviceCall: SingleUseSuspendedOperation

                init(serviceCall: SingleUseSuspendedOperation) {
                    self.serviceCall = serviceCall
                }

                func nextColor() async -> String {
                    await serviceCall.suspendUntilReleased()
                    return Constants.expectedColor
                }
            }

            struct ColorHandler: Sendable {
                enum NewColor: RequestResponsePayloadHandler {
                    typealias ResponsePayload = String
                }

                private let colorService: ColorServiceProtocol

                init(colorService: ColorServiceProtocol) {
                    self.colorService = colorService
                }

                var handlers: [any Handlable] {
                    [
                        NewColor.handlerRegistration {
                            await colorService.nextColor()
                        },
                    ]
                }
            }

            let serviceCall = SingleUseSuspendedOperation()
            let colorService = ColorService(serviceCall: serviceCall)
            let colorHandler = ColorHandler(colorService: colorService)
            var eventBus: EventBus? = EventBus(defaultTimeout: .milliseconds(Constants.timeoutMilliseconds))
            weak var weakEventBus = eventBus
            eventBus?.register(handlers: colorHandler.handlers)

            let responseTask: Task<ColorHandler.NewColor.TrackedResponse, Error>
            if let eventBus {
                responseTask = Task {
                    try await ColorHandler.NewColor.sendAndWaitForResponse(
                        eventBus: eventBus,
                        timeout: .milliseconds(Constants.timeoutMilliseconds)
                    )
                }
            } else {
                Issue.record("Expected EventBus to exist before sending event")
                return
            }
            await serviceCall.waitUntilSuspended()

            eventBus = nil
            #expect(weakEventBus != nil)

            await serviceCall.release()
            let response = try await responseTask.value

            #expect(response.busEvent.payload == Constants.expectedColor)
            #expect(weakEventBus == nil)
        }

        @Test
        func nestedServiceHandlerDeallocationExample() async throws {
            protocol ColorServiceProtocol: Sendable {
                func nextColor() async -> String
            }

            actor ColorService: ColorServiceProtocol {
                private let serviceCall: SingleUseSuspendedOperation

                init(serviceCall: SingleUseSuspendedOperation) {
                    self.serviceCall = serviceCall
                }

                func nextColor() async -> String {
                    await serviceCall.suspendUntilReleased()
                    return Constants.expectedColor
                }
            }

            struct ColorHandler: Sendable {
                enum NewColor: RequestResponsePayloadHandler {
                    typealias ResponsePayload = String
                }

                private let colorService: ColorServiceProtocol

                init(colorService: ColorServiceProtocol) {
                    self.colorService = colorService
                }

                var handlers: [any Handlable] {
                    [
                        NewColor.handlerRegistration {
                            await colorService.nextColor()
                        },
                    ]
                }
            }

            struct FavoriteColorController: Sendable {
                enum FavoriteColor: RequestResponseTrackedBusEventHandler {
                    typealias ResponsePayload = String
                }

                var handlers: [any Handlable] {
                    [
                        FavoriteColor.handlerRegistration { inputEvent in
                            guard let colorResponse = try await ColorHandler.NewColor.sendAndWaitForResponse(
                                inputEvent: inputEvent
                            ) else {
                                return nil
                            }

                            return await colorResponse.appendEvent(
                                FavoriteColor.response(payload: colorResponse.busEvent.payload)
                            )
                        },
                    ]
                }
            }

            let serviceCall = SingleUseSuspendedOperation()
            let colorService = ColorService(serviceCall: serviceCall)
            let colorHandler = ColorHandler(colorService: colorService)
            let favoriteColorController = FavoriteColorController()
            var eventBus: EventBus? = EventBus(defaultTimeout: .milliseconds(Constants.timeoutMilliseconds))
            weak var weakEventBus = eventBus
            eventBus?.register(handlers: colorHandler.handlers)
            eventBus?.register(handlers: favoriteColorController.handlers)

            let responseTask: Task<FavoriteColorController.FavoriteColor.TrackedResponse, Error>
            if let eventBus {
                responseTask = Task {
                    try await FavoriteColorController.FavoriteColor.sendAndWaitForResponse(
                        eventBus: eventBus,
                        timeout: .milliseconds(Constants.timeoutMilliseconds)
                    )
                }
            } else {
                Issue.record("Expected EventBus to exist before sending event")
                return
            }
            await serviceCall.waitUntilSuspended()

            eventBus = nil
            #expect(weakEventBus != nil)

            await serviceCall.release()
            let response = try await responseTask.value

            #expect(response.busEvent.payload == Constants.expectedColor)
            #expect(weakEventBus == nil)
        }
    }
}

// swiftlint:enable nesting
