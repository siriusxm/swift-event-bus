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

@Suite("EventBusTests")
enum EventBusExampleTests {
    @Suite("EventBus ReadMe Example tests")
    struct EventBusReadMeExampleTests {
        @Test
        func readMeExample1() async throws {
            struct SystemConfig: Sendable {
                let preference = "good"
            }

            // Here is a minimal service that defines one event and a handler for that event
            struct Service1: Sendable {
                // RequestResponsePayloadHandler is a protocol with extensive default functions and definitions.
                // It defines request and response event types, as well as functions to send events and register handler functions
                enum EventHandler1: RequestResponsePayloadHandler {}
                let config: SystemConfig
                let handlers: [any Handlable]
                init(config: SystemConfig) {
                    self.config = config
                    // Here the handlerRegistration function is used to tie a handler function to the RequestResponsePayloadHandler's events.
                    // The function here is a simple void closure expressed inline.
                    // Note we use the init to pass its parameters as local inline references to the handler's closure.
                    // This avoids self in the handler closure, which would run afoul of swift's chicken-and-egg init problem (pun intended).
                    // Examples in the "separating services and handlers" doc show functions with parameters and return data.
                    handlers = [EventHandler1.handlerRegistration { logger.info("service 1 invoked with preference: \(config.preference)", tag: "eventBus") }]
                }
            }

            // Here is a minimal system with one service and an EventBus
            struct MySystem: Sendable {
                let eventBus: EventBus
                let service1: Service1

                init(config: SystemConfig) {
                    eventBus = EventBus()
                    service1 = Service1(config: config)
                    // This registration function is the single required thing for users to call to start using the EventBus
                    eventBus.register(handlers: service1.handlers)
                }

                // It is a best practice for a system using the EventBus to publish a top-level API for its users to access its services
                // Here the service function returns a TrackedResponse, which in a real application would be overkill to expose.
                // In a test, however, this response allows us to check the type of the double-void event to make sure the right response was returned.
                func doService1() async throws -> Service1.EventHandler1.TrackedResponse? {
                    // Notice here events know how to send themselves into the bus,
                    // ..and the internal event IDs are guaranteed to hook through to the registered function for the event.
                    // This is implemented with simple reusable protocol extension functions, no macro magic or generated code,
                    // ..so it can be easliy traced through at runtime if you are curious about the integration details.
                    try await Service1.EventHandler1.sendAndWaitForResponse(eventBus: eventBus)
                }
            }

            // Here we instantiate our system, invoke its service, and check to make sure the service executed and returned the expected type of response
            let mySystem = MySystem(config: SystemConfig())
            let response = try? await mySystem.doService1()
            #expect(response?.busEvent.eventType == Service1.EventHandler1.responseID)
        }

        @Test
        func readMeExample2() async {
            // In this example, we are just sending a "fire and forget" event with nothing handling it and want to test the event is being sent.
            // This is tricky to test. It's easier to register a handler so the test can wait to see if the handler was called as in example 1.
            // In this example we're going to demo jumping a few hoops to compensate, and you can compare to other examples using sendAndWait.
            // The first hoop we jump is a boxed variable we use to set a test flag from an embedded logging function in the test.
            // This allows us to keep the MySystem class Sendable and hook the log function through its initializer without offending swift.
            class Box<T>: @unchecked Sendable {
                var value: T
                init(_ value: T) {
                    self.value = value
                }
            }

            final class MySystem: Sendable {
                enum LunchTime: SimpleBusEventType {}
                let eventBus: EventBus
                let flagWrapper: Box<Bool>

                init(flagWrapper: Box<Bool>) {
                    self.flagWrapper = flagWrapper
                    // The EventBus has a built in logger that allows you to define "LogPoints" that you can save and reuse for specific events.
                    // Here, since the logger is the only entity that's responding to the event, we're stretching the log function to set a test flag.
                    // Then we can automatically check if the event was sent using a test expectation rather than manually reading the log message.
                    // But coding this way has the downside of relying on EventBus internals for a consistent test. See comments below.
                    let logger = EventBusLogger(
                        logPoints: [
                            LogPoint(
                                logPointType: .sent,
                                eventType: LunchTime.eventType,
                                formatPayload: {
                                    flagWrapper.value = true
                                    return "LunchTime event sent to EventBus"
                                }
                            ),
                        ]
                    )
                    eventBus = EventBus(eventBusLogger: logger)
                }

                func lunchLoop() async {
                    // in production, we'd do something like this:
                    //                    for await _ in AsyncTimerSequence(interval: .seconds(1)) {
                    //                        if isNoon(Date()) {
                    //                            await LunchTime.send(eventBus: eventBus)
                    //                        }
                    //                    }
                    // For testing, we send one event immediately and then return.
                    // In a production system, we'd use a MySystem mock for tests. Here it's all for testing anyway, so no need for a separate mock.
                    await LunchTime.send(eventBus: eventBus)
                }
            }

            // When you run this test, you can check the console for the EventBusLogger's message the event was sent.
            // Our test logger code will also automatically set the flag that the function was called as expected so the test will pass.
            let flagWrapper = Box(false)
            let mySystem = MySystem(flagWrapper: flagWrapper)
            // There is a tricky nuance here worth explaining. Normally code like the following is suspicious and can lead to test race conditions.
            // I.e. Generally when you call an async function, you are not guaranteed it will operate atomically without yielding.
            // A symptom would be a test that passes when run by itself, but intermittently fails expectations when run with other tests, or on CI.
            // Here we can get away with this consistently by relying on the internals of EventBus.send.
            // It calls the logger function we're using before any yield, so our test variable will be set before the async function returns.
            // It is best practice not to rely on stuff like this, so better to test event sending by integration testing with a handler,
            // ..even an artificial test handler as we put into example 1 above.
            // This enables us to use a production sendAndWait function where we can insure the handler function runs before the async function returns.
            await mySystem.lunchLoop()
            #expect(flagWrapper.value)
        }

        // swiftlint:disable nesting
        @Test
        func readMeExample3() async {
            // In this example, we'll demonstrate some best practices for creating a stateless service that responds to a "fire and forget" event.
            struct SamService: Sendable {
                // First, we define the payload of the result event for our lunch handling function
                // It's best to err on the side of including any data that may be useful to downstream handlers or maintenance developers
                // This example records a timestamp when lunch occurred, and a result of what happened at lunch
                struct LunchRecord {
                    let time: Date

                    enum Result: String, CaseIterable {
                        case finishedLunch
                        case ateSomeOfLunch
                        case skippedLunch
                    }

                    let result: Result
                }

                // This ResponsePayloadHandler is used to integrate a handler function that responds to the triggering LunchTime event,
                // and returns it's own response event.
                // Protocol extension functions inside ResponsePayloadHandler do all the integration work and event hookup.
                enum SamLunch: ResponsePayloadHandler {
                    typealias TriggerEvent = MySystem.LunchTime
                    typealias ResponsePayload = LunchRecord
                }

                // Because this service is so simple, we can declare the handlers array as a let constant
                // with the handler function as a closure inline.
                // But the bar to do this is very high, mainly that the handler closure can't reference the service's self,
                // ..or you run into swift's issues with referencing self before all the members are initialized.
                // The main solutions for this are to declare the handlers array as a lazy var if all the handlers are declared here,
                // or as a computed var in an extension if some handlers are declared in extensions. Examples are included in the "separating handlers and services" docs.
                let handlers: [any Handlable] = [
                    SamLunch.handlerRegistration {
                        LunchRecord(time: Date(), result: LunchRecord.Result.allCases.randomElement() ?? .skippedLunch)
                    },
                ]
            }

            // Here we code MySystem to look slightly more realistic in that it takes init variables for the EventBus and its services.
            // This allows tests to configure the EventBus with Loggers and shorter timeouts for tests as needed,
            // to use the EventBus to call test event sending functions, and to inject mock services as needed.
            final class MySystem: Sendable {
                enum LunchTime: SimpleBusEventType {}
                let eventBus: EventBus
                let samService: SamService

                init(eventBus: EventBus, samService: SamService) {
                    self.eventBus = eventBus
                    self.samService = samService
                    eventBus.register(handlers: samService.handlers)
                }
            }

            // Here we're using the EventBusLogger in a standard way to log 3 things:
            // 1. the trigger event was sent into the EventBus as expected,
            // 2. the EventBus directed the trigger event to a handler (note the Event Sequence Index is the same as for 1), and
            // 3. that the expected SamService handler ran in response with results (and the response event gets a new Event Sequence Index)
            let logger = EventBusLogger(
                logPoints: [
                    LogPoint(
                        logPointType: .sent,
                        eventType: MySystem.LunchTime.eventType,
                        formatPayload: { "LunchTime event sent to EventBus" }
                    ),
                    LogPoint(
                        logPointType: .enteredHandler,
                        eventType: MySystem.LunchTime.eventType,
                        formatPayload: { "LunchTime event successfully dispatched to a handler" }
                    ),
                    LogPoint(
                        logPointType: .responded,
                        eventType: SamService.SamLunch.responseID,
                        formatPayload: { (payload: SamService.LunchRecord) in
                            "Sam's lunchtime was: \(payload.time), and he: \(payload.result)"
                        }
                    ),
                ]
            )

            // Here is the system "main loop" or test code. We left out the "lunchLoop" function from the previous example,
            // so here we're taking advantage of the SamLunch ResponsePayloadHandler to send a test event and wait for the response.
            // Note the short defaultTimeout value here, used to keep tests running quickly, insuring the EventBus is not stalling
            let eventBus = EventBus(eventBusLogger: logger, defaultTimeout: .milliseconds(300))
            let samService = SamService()
            _ = MySystem(eventBus: eventBus, samService: samService)
            // This test is demonstrating that you can use a sendAndWaitForResponse function in a test to re-synchronize the async handler code.
            // This shows that the date generated in the test handler happens at a deterministic time after the event is sent and before it returns.
            let before = Date()
            let result = try? await SamService.SamLunch.sendAndWaitForResponse(eventBus: eventBus)
            let after = Date()
            #expect(result?.busEvent.payload.result != nil)
            #expect(result?.busEvent.payload.time ?? Date.distantPast > before)
            #expect(result?.busEvent.payload.time ?? Date.distantFuture < after)
        }

        // swiftlint:enable nesting
    }
}

extension EventBusExampleTests.EventBusReadMeExampleTests {
    @Test
    func readMeExample4() async {
        // In this example, we'll demonstrate RequestResponseHandlers, TrackedBusEvents and TrackedBusEventHandlers
        struct ColoredFoodService: Sendable {
            // Here is the request-response handler/event declaration, it defines request and response events inside
            // The design goal was to allow end-point services to publish their APIs as events with minimum boilerplate
            // Payload types are defaulted to Void if no type alias is declared
            enum ColoredFoodDelivery: RequestResponsePayloadHandler {
                typealias ResponsePayload = String
            }

            // Payload handlers are no more complex for request-response than for response handlers
            // Here is the simplest possible handler that returns a hard-coded string
            // Since we're introducing TrackedBusEventHandlers below, we can contrast them to PayloadHandlers like this one
            // The EventBus always deals internally with TrackedBusEvents that contain indices, back-pointers, and history
            // But for PayloadHandlers the event protocols have glue code that does a lot of automated integration:
            // - it extracts the event payload and passes it to the PayloadHandler function as its parameter
            //     - in this case, the ReqestPayload is defaulted to Void, so there is no input parameter
            // - it takes the function return, packages it into a response event, and sends it
            // - it hooks the request event through to the response event so they show up in the TrackedBusEvent history
            // ..all this to provide standard integration and troubleshooting features without developer boilerplate
            let handlers: [any Handlable] = [ColoredFoodDelivery.handlerRegistration { "Green eggs and ham" }]
        }

        // the LunchRecord is as above except now it records what food was eaten for lunch
        struct SamService: Sendable {
            struct LunchRecord {
                let time: Date
                let food: String

                enum Result: String, CaseIterable {
                    case finishedLunch
                    case ateSomeOfLunch
                    case skippedLunch
                }

                let result: Result
            }

            // to allow us to call back into the EventBus inside the handler,
            // we this example uses a TrackedBusEventHandler rather than a PayloadHandler
            enum SamLunch: ResponseTrackedBusEventHandler {
                typealias TriggerEvent = MySystem.LunchTime
                typealias ResponsePayload = LunchRecord
            }

            let handlers: [any Handlable] = [
                // A TrackedBusEventHandler takes the event that triggered the handler as its input parameter
                // This gives the handler writer the power to call back into the EventBus with events as subroutines
                // ..at the expense of requiring the writer to manually hook through the events into the function return
                // This function can be turned into a single statement with two pipeline functions - see pipeline example in the docs folder
                SamLunch.handlerRegistration { (inputEvent: MySystem.LunchTime.TrackedEvent) in
                    // To call a request-response event from inside a handler, we pass in the inputEvent
                    // the RequestResponseHandler code declares this sendAndWait version that integrates with the inputEvent
                    let foodResponse = try await ColoredFoodService.ColoredFoodDelivery.sendAndWaitForResponse(
                        inputEvent: inputEvent
                    )
                    // To return from a TrackedBusEventHandler, we create a response event
                    // using the response utility the SamLunch event handler definition declares
                    // and we chain this function's response into the foodResponse from the ColoredFoodDelivery event.
                    // Why is the foodResponse optional? Specifically to handle when the EventBus is being deallocated.
                    // So if you ever see a nil response from a sendAndWait call, just return.
                    // This allows the system to be deallocated with no stalls or crashes. See the deallocation example in the docs folder.
                    return await foodResponse?.appendEvent(SamLunch.response(
                        payload: LunchRecord(
                            time: Date(),
                            food: foodResponse?.busEvent.payload ?? "",
                            result: LunchRecord.Result.allCases.randomElement() ?? .skippedLunch
                        )
                    ))
                },
            ]
        }

        final class MySystem: Sendable {
            enum LunchTime: SimpleBusEventType {}
            let eventBus: EventBus
            let samService: SamService
            let coloredFoodService: ColoredFoodService

            init(eventBus: EventBus, samService: SamService, coloredFoodService: ColoredFoodService) {
                self.eventBus = eventBus
                self.samService = samService
                self.coloredFoodService = coloredFoodService
                eventBus.register(handlers: samService.handlers + coloredFoodService.handlers)
            }
        }

        let logger = EventBusLogger(
            logPoints: [
                LogPoint(
                    logPointType: .sent,
                    eventType: MySystem.LunchTime.eventType,
                    formatPayload: { "LunchTime event sent to EventBus" }
                ),
                LogPoint(
                    logPointType: .enteredHandler,
                    eventType: MySystem.LunchTime.eventType,
                    formatPayload: { "LunchTime event successfully dispatched to a handler" }
                ),
                LogPoint(
                    logPointType: .enteredHandler,
                    eventType: ColoredFoodService.ColoredFoodDelivery.requestID,
                    formatPayload: { "ColoredFoodDelivery request successfully dispatched to a handler" }
                ),
                LogPoint(
                    logPointType: .responded,
                    eventType: ColoredFoodService.ColoredFoodDelivery.responseID,
                    formatPayload: { (payload: String) in
                        "ColoredFoodDelivery service responded with: \(payload)"
                    }
                ),
                LogPoint(
                    logPointType: .responded,
                    eventType: SamService.SamLunch.responseID,
                    formatPayload: { (payload: SamService.LunchRecord) in
                        "Sam's lunchtime was: \(payload.time), and he: \(payload.result) of \(payload.food)"
                    }
                ),
            ]
        )

        let eventBus = EventBus(eventBusLogger: logger)
        let samService = SamService()
        let coloredFoodService = ColoredFoodService()
        _ = MySystem(eventBus: eventBus, samService: samService, coloredFoodService: coloredFoodService)
        let result = try? await SamService.SamLunch.sendAndWaitForResponse(eventBus: eventBus)
        #expect(result?.busEvent.payload.result != nil)
        #expect(result?.busEvent.payload.food == "Green eggs and ham")
        // the result has 4 events in its history:
        // the MySystem.LunchTime event that started the process
        // the ColoredFoodService.ColoredFoodDelivery request sent by the SamLunch handler
        // the ColoredFoodService.ColoredFoodDelivery response containing the food
        // the SamService.SamLunch response with the accumulated results and history
        #expect(result?.eventHistory.count == 4)
    }
}
