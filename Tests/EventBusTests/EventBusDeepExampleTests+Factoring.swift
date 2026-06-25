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
@Suite("EventBus deep dive examples")
enum EventBusDeepExampleTests {
    @Suite("EventBus ReadMe Example tests")
    struct EventBusDeepExampleTestsFactoring {
        @Test
        func everythingIsSendableExample() {
            class NonSendableThing {
                init() {}
            }

            enum ImpossibleEvent: SimpleBusEventType {
                // you cannot uncomment the below line or it will get the below compiler error
                // typealias Payload = NonSendableThing
                // Type 'ImpossibleEvent.Payload' (aka 'NonSendablePayload') does not conform to the 'Sendable' protocol
            }

            // This struct is non-sendable because it contains a non-sendable member variable
            // ..so you can't use it as a handler class - you can't register its functions with the EventBus as handlers
            struct NonSendableHandler {
                var thing = NonSendableThing()

                enum ImpossibleHandlerEvent: RequestResponsePayloadHandler {
                    typealias ResponsePayload = String
                }

                func makeString() -> String {
                    "Green eggs and ham"
                }

                // cannot uncomment the below line or it will get the below error
                // the problem is the "makeString" function is a member of NonSendableHandler
                // lazy var handlers: [any Handlable] = [ImpossibleHandlerEvent.handlerRegistration(makeString)]
                // Converting non-Sendable function value to ['@Sendable (()) async throws -> String'] may introduce data races
            }
            // var nonSendableHandler = NonSendableHandler()
            let eventBus = EventBus()
            // eventBus.register(handlers: nonSendableHandler.handlers)

            // the only correction from above is to make the handler and its members sendable
            final class SendableThing: Sendable {
                init() {}
            }

            enum PossibleEvent: SimpleBusEventType {
                typealias Payload = SendableThing
            }

            struct SendableHandler {
                let thing = SendableThing()

                enum PossibleHandlerEvent: RequestResponsePayloadHandler {
                    typealias ResponsePayload = String
                }

                func makeString() -> String {
                    "Green eggs and ham"
                }

                // now this works fine, you can reference the makeString function as sendable
                lazy var handlers: [any Handlable] = [PossibleHandlerEvent.handlerRegistration(makeString)]
            }
            var sendableHandler = SendableHandler()
            eventBus.register(handlers: sendableHandler.handlers)
        }

        @Test
        func separatingServicesAndHandlersExample() async throws {
            protocol ColorServiceProtocol: Sendable {
                func nextValidColor() async -> String
                func colorByIndex(_ index: Int) async -> String?
            }

            actor StatefulColorService: ColorServiceProtocol {
                // This service is stateful because it maintains a list of valid colors that can change over time
                private var validColors = [
                    "Green", "Red", "Orange", "Yellow", "Blue", "Purple", "White", "Black",
                ]
                private var colorIndex = 0

                var colorCount: Int {
                    validColors.count
                }

                // These functions aren't part of the protocol - they're for setup, admin, or testing.
                // Direct calls create code dependencies, which is fine for:
                // - Tests that own service instances
                // - Factory code that configures services before handing them to the EventBus
                // Other direct access should be intentional and well-justified to create code dependencies.
                func isValidColor(_ color: String) -> Bool {
                    validColors.contains(color)
                }

                func addColor(_ color: String) {
                    validColors.append(color)
                }

                // These next two functions will be used in the example by the handler
                func nextValidColor() async -> String {
                    let localIndex = colorIndex
                    colorIndex = (localIndex + 1) % colorCount
                    return validColors[localIndex]
                }

                // This is here to show off translation of data types in the handler
                // In a real-world example, allowing a color choice by index would be an encapsulation violation
                func colorByIndex(_ index: Int) async -> String? {
                    validColors[safeIndex: index]
                }
            }

            // Now the handler can be stateless and still interface with a stateful service
            // ..and can translate between shared data models and the service's local data
            struct ColorHandler: Sendable {
                enum NewColor: RequestResponsePayloadHandler {
                    typealias ResponsePayload = String
                }

                enum ColorByIndex: RequestResponsePayloadHandler {
                    // The "shared I/O data type" the handler uses is a Float here,
                    // ..as opposed to the Int used by the service
                    typealias RequestPayload = Float
                    typealias ResponsePayload = String?
                }

                // The basic shape is the handler owns an instance of the service,
                // the handler's instance of the service is its only presence in the app outside of the factory/init,
                // ..and the handler is only accessed by the EventBus through its registered functions
                // This way the EventBus owner can deallocate the whole system atomically without retain cycles
                private let colorService: ColorServiceProtocol
                init(colorService: ColorServiceProtocol) {
                    self.colorService = colorService
                }

                // Here the handlers array is defined as a computed variable with closures as the handler functions
                // They could also be defined as member functions in the handler and referenced here
                var handlers: [any Handlable] {
                    [
                        // Best practice is for handler functions calling services to be as simple as possible
                        // Only do data translation/access, and delegate all logic to the service
                        NewColor.handlerRegistration { await colorService.nextValidColor() },
                        // here the handler does the data translation for the service from Float to Int
                        ColorByIndex.handlerRegistration { floatIndex in
                            await colorService.colorByIndex(Int(floatIndex))
                        },
                    ]
                }
            }

            // The test creates the system, configures the handler with the service,
            // and registers the handler on the event bus
            let eventBus = EventBus()
            let colorService = StatefulColorService()
            let colorHandler = ColorHandler(colorService: colorService)
            eventBus.register(handlers: colorHandler.handlers)

            // To test the handler/service integration, the test sends events in to the bus and waits for results
            let colorResult = try await ColorHandler.NewColor.sendAndWaitForResponse(
                eventBus: eventBus, timeout: .milliseconds(300)
            )
            // The test retained a service instance and can call its utilities or check its state
            let isFirstColorValid = await colorService.isValidColor(colorResult.busEvent.payload)
            #expect(isFirstColorValid)

            // The test manipulates the service's state by adding a new color
            var colorResultSet = Set<String>([])
            let differentColor = "Taupe"
            await colorService.addColor(differentColor)

            // ..and tests the second event type and checks that all result colors are still valid
            for index in await 0 ..< colorService.colorCount {
                let result = try await ColorHandler.ColorByIndex.sendAndWaitForResponse(
                    eventBus: eventBus, payload: Float(index), timeout: .milliseconds(100)
                )
                let color = try #require(result.busEvent.payload, "Expected color at index \(index)")
                colorResultSet.insert(color)
                let isColorValid = await colorService.isValidColor(color)
                #expect(isColorValid)
            }
            // finally the test ensures the new color was returned by the service
            #expect(colorResultSet.contains(differentColor))
        }
    }
}

// swiftlint:enable nesting
