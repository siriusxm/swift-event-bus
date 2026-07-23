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

private enum DeallocColorError: Error, Equatable {
    case missingColor
}

private actor DeallocColorService {
    private let expectedColor: String
    private let operation: SingleUseSuspendedOperation

    init(expectedColor: String, operation: SingleUseSuspendedOperation) {
        self.expectedColor = expectedColor
        self.operation = operation
    }

    func nextColor() async -> String {
        await operation.suspendUntilReleased()
        return expectedColor
    }

    func throwingColor() async throws -> String {
        await operation.suspendUntilReleased()
        throw DeallocColorError.missingColor
    }
}

private actor DeallocTwoColorService {
    private let expectedColor: String
    private let firstCall: SingleUseSuspendedOperation
    private let firstRequest: String
    private let secondCall: SingleUseSuspendedOperation

    init(
        expectedColor: String,
        firstCall: SingleUseSuspendedOperation,
        firstRequest: String,
        secondCall: SingleUseSuspendedOperation
    ) {
        self.expectedColor = expectedColor
        self.firstCall = firstCall
        self.firstRequest = firstRequest
        self.secondCall = secondCall
    }

    func nextColor(for request: String) async -> String {
        if request == firstRequest {
            await firstCall.suspendUntilReleased()
        } else {
            await secondCall.suspendUntilReleased()
        }
        return expectedColor
    }
}

extension EventBusDeepExampleTests {
    @Suite("EventBus deallocation edge cases")
    struct EventBusDeallocEdgeCases {
        private enum Constants {
            static let deallocationWaitAttemptRange = 0 ..< 50
            static let deallocationWaitInterval: Duration = .milliseconds(1)
            static let expectedColor = "Green"
            static let firstColorRequest = "first"
            static let secondColorRequest = "second"
            static let timeoutMilliseconds = 300
        }

        @Test
        func fireAndForgetHandlerDeallocationExample() async {
            enum FireAndForgetColor: RequestResponsePayloadHandler {
                typealias ResponsePayload = String
            }

            let serviceCall = SingleUseSuspendedOperation()
            let colorService = DeallocColorService(
                expectedColor: Constants.expectedColor,
                operation: serviceCall
            )
            var eventBus: EventBus? = EventBus(defaultTimeout: .milliseconds(Constants.timeoutMilliseconds))
            weak var weakEventBus = eventBus
            eventBus?.register(handlers: [
                FireAndForgetColor.handlerRegistration {
                    await colorService.nextColor()
                },
            ])

            if let eventBus {
                await FireAndForgetColor.send(eventBus: eventBus)
            } else {
                Issue.record("Expected EventBus to exist before sending event")
                return
            }
            await serviceCall.waitUntilSuspended()

            eventBus = nil
            #expect(weakEventBus != nil)

            await serviceCall.release()
            await serviceCall.waitUntilFinished()
            await waitUntilEventBusDeallocated { weakEventBus }

            #expect(weakEventBus == nil)
        }

        @Test
        func throwingServiceHandlerDeallocationExample() async throws {
            enum ThrowingColor: RequestResponsePayloadHandler {
                typealias ResponsePayload = String
            }

            let serviceCall = SingleUseSuspendedOperation()
            let colorService = DeallocColorService(
                expectedColor: Constants.expectedColor,
                operation: serviceCall
            )
            var eventBus: EventBus? = EventBus(defaultTimeout: .milliseconds(Constants.timeoutMilliseconds))
            weak var weakEventBus = eventBus
            eventBus?.register(handlers: [
                ThrowingColor.handlerRegistration {
                    try await colorService.throwingColor()
                },
            ])

            let responseTask: Task<ThrowingColor.TrackedResponse, Error>
            if let eventBus {
                responseTask = Task {
                    try await ThrowingColor.sendAndWaitForResponse(
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
            do {
                _ = try await responseTask.value
                Issue.record("Expected service error")
            } catch {
                #expect(error as? DeallocColorError == .missingColor)
            }
            await waitUntilEventBusDeallocated { weakEventBus }

            #expect(weakEventBus == nil)
        }

        @Test
        func restartHandlerDeallocationExample() async {
            enum RestartColor: RequestResponseTrackedBusEventHandler {
                typealias ResponsePayload = String

                static let concurrencyType: EventBus.ConcurrencyType = .restart
            }

            let serviceCall = SingleUseSuspendedOperation()
            let colorService = DeallocColorService(
                expectedColor: Constants.expectedColor,
                operation: serviceCall
            )
            var eventBus: EventBus? = EventBus(defaultTimeout: .milliseconds(Constants.timeoutMilliseconds))
            weak var weakEventBus = eventBus
            eventBus?.register(handlers: [
                RestartColor.handlerRegistration { inputEvent in
                    let color = await colorService.nextColor()
                    return await inputEvent.appendEvent(RestartColor.response(payload: color))
                },
            ])

            if let eventBus {
                await RestartColor.send(eventBus: eventBus)
            } else {
                Issue.record("Expected EventBus to exist before sending event")
                return
            }
            await serviceCall.waitUntilSuspended()

            eventBus = nil
            #expect(weakEventBus != nil)

            await serviceCall.release()
            await serviceCall.waitUntilFinished()
            await waitUntilEventBusDeallocated { weakEventBus }

            #expect(weakEventBus == nil)
        }

        @Test
        func parallelHandlersDeallocateAfterInFlightHandlersFinish() async {
            enum ParallelColor: RequestResponsePayloadHandler {
                typealias RequestPayload = String
                typealias ResponsePayload = String
            }

            let firstCall = SingleUseSuspendedOperation()
            let secondCall = SingleUseSuspendedOperation()
            let colorService = DeallocTwoColorService(
                expectedColor: Constants.expectedColor,
                firstCall: firstCall,
                firstRequest: Constants.firstColorRequest,
                secondCall: secondCall
            )
            var eventBus: EventBus? = EventBus(defaultTimeout: .milliseconds(Constants.timeoutMilliseconds))
            weak var weakEventBus = eventBus
            eventBus?.register(handlers: [
                ParallelColor.handlerRegistration { request in
                    await colorService.nextColor(for: request)
                },
            ])

            if let eventBus {
                await ParallelColor.send(eventBus: eventBus, payload: Constants.firstColorRequest)
                await ParallelColor.send(eventBus: eventBus, payload: Constants.secondColorRequest)
            } else {
                Issue.record("Expected EventBus to exist before sending event")
                return
            }
            await firstCall.waitUntilSuspended()
            await secondCall.waitUntilSuspended()

            eventBus = nil
            #expect(weakEventBus != nil)

            await firstCall.release()
            await firstCall.waitUntilFinished()
            #expect(weakEventBus != nil)

            await secondCall.release()
            await secondCall.waitUntilFinished()
            await waitUntilEventBusDeallocated { weakEventBus }

            #expect(weakEventBus == nil)
        }

        private func waitUntilEventBusDeallocated(_ eventBus: () -> EventBus?) async {
            for _ in Constants.deallocationWaitAttemptRange {
                if eventBus() == nil {
                    return
                }
                try? await Task.sleep(for: Constants.deallocationWaitInterval)
            }
        }
    }
}
