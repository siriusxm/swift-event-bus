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

// Macro integration declarations and their end-to-end tests intentionally stay in one fixture file.
// swiftlint:disable file_length

@SimpleBusEventTypes
enum MacroSimpleEvent: SimpleBusEventType {
    typealias Payload = String
}

extension MacroSimpleEvent.TrackedEvent {
    func macroSimpleMarker() -> String {
        "simple macro alias works"
    }
}

enum MacroResponseTriggerEvent: SimpleBusEventType {
    typealias Payload = Void
}

struct MacroSimplePayload {
    let message: String
    let count: Int

    @BusEventPayloadInit
    init(message: String, count: Int = 1) {
        self.message = message
        self.count = count
    }
}

@SimpleBusEventPayloadAndTypes("message", "count")
enum MacroPayloadDrivenEvent: SimpleBusEventType {
    typealias Payload = MacroSimplePayload
}

struct MacroLabeledPayload {
    let value: String
    let apiValue: Int
    let repeated: Bool

    @BusEventPayloadInit
    init(_ value: String, apiValue localValue: Int, `repeat`: Bool = false) {
        self.value = value
        apiValue = localValue
        repeated = `repeat`
    }
}

@SimpleBusEventPayloadAndTypes("value", "apiValue", "repeat")
enum MacroLabeledPayloadEvent: SimpleBusEventType {
    typealias Payload = MacroLabeledPayload
}

enum MacroResponsePayloadTriggerEvent: SimpleBusEventType {
    typealias Payload = MacroSimplePayload
}

@ResponseHandlerPayloadAndTypes(triggerEvent: ["message", "count"])
enum MacroPayloadResponseHandler: ResponsePayloadHandler {
    typealias TriggerEvent = MacroResponsePayloadTriggerEvent
    typealias ResponsePayload = String
}

@ResponseHandlerPayloadAndTypes(triggerEvent: ["message", "count"])
enum MacroTrackedResponseHandler: ResponseTrackedBusEventHandler {
    typealias TriggerEvent = MacroResponsePayloadTriggerEvent
    typealias ResponsePayload = String
}

@ResponseHandlerTypes
enum MacroResponseHandler: ResponsePayloadHandler {
    typealias TriggerEvent = MacroResponseTriggerEvent
    typealias ResponsePayload = String
}

extension MacroResponseHandler.TrackedTriggerEvent {
    func macroResponseTriggerMarker() -> String {
        "response trigger alias works"
    }
}

extension MacroResponseHandler.TrackedResponse {
    func macroResponseMarker() -> String {
        "response alias works"
    }
}

@RequestResponseHandlerTypes
enum MacroRequestResponseHandler: RequestResponsePayloadHandler {
    typealias RequestPayload = String
    typealias ResponsePayload = Int
}

@RequestResponseHandlerPayloadAndTypes(request: ["message", "count"])
enum MacroPayloadRequestResponseHandler: RequestResponsePayloadHandler {
    typealias RequestPayload = MacroSimplePayload
    typealias ResponsePayload = String
}

@RequestResponseHandlerPayloadAndTypes(request: ["message", "count"])
enum MacroTrackedRequestResponseHandler: RequestResponseTrackedBusEventHandler {
    typealias RequestPayload = MacroSimplePayload
    typealias ResponsePayload = String
}

extension MacroRequestResponseHandler.TrackedRequest {
    func macroRequestMarker() -> String {
        "request alias works"
    }
}

extension MacroRequestResponseHandler.TrackedResponse {
    func macroRequestResponseMarker() -> String {
        "request response alias works"
    }
}

struct MacroResponseData {
    let label: String
    let score: Int

    @BusEventPayloadInit
    init(label: String, score: Int = 0) {
        self.label = label
        self.score = score
    }
}

@ResponseHandlerPayloadAndTypes(triggerEvent: ["message", "count"], response: ["label", "score"])
enum MacroResponseBuilderHandler: ResponseTrackedBusEventHandler {
    typealias TriggerEvent = MacroResponsePayloadTriggerEvent
    typealias ResponsePayload = MacroResponseData
}

@RequestResponseHandlerPayloadAndTypes(request: ["message", "count"], response: ["label", "score"])
enum MacroRequestResponseBuilderHandler: RequestResponseTrackedBusEventHandler {
    typealias RequestPayload = MacroSimplePayload
    typealias ResponsePayload = MacroResponseData
}

enum MacroReportResponseEvent: SimpleBusEventType {
    typealias Payload = MacroResponseData
}

@LinkedEventHandlerPayloadAndTypes(triggerEvent: ["message", "count"], response: ["label", "score"])
enum MacroLinkedPayloadBuilderHandler: LinkedEventPayloadHandler {
    typealias TriggerEvent = MacroResponsePayloadTriggerEvent
    typealias ResponseEvent = MacroReportResponseEvent
}

enum MacroLinkTriggerEvent: SimpleBusEventType {
    typealias Payload = String
}

enum MacroLinkResponseEvent: SimpleBusEventType {
    typealias Payload = Int
}

@LinkedEventHandlerTypes
enum MacroLinkedPayloadHandler: LinkedEventPayloadHandler {
    typealias TriggerEvent = MacroLinkTriggerEvent
    typealias ResponseEvent = MacroLinkResponseEvent
}

enum MacroLinkTrackedTriggerEvent: SimpleBusEventType {
    typealias Payload = Double
}

enum MacroLinkTrackedResponseEvent: SimpleBusEventType {
    typealias Payload = Bool
}

@LinkedEventHandlerTypes
enum MacroLinkedTrackedHandler: LinkedTrackedBusEventHandler {
    typealias TriggerEvent = MacroLinkTrackedTriggerEvent
    typealias ResponseEvent = MacroLinkTrackedResponseEvent
}

extension MacroLinkedPayloadHandler.TrackedTriggerEvent {
    func macroLinkTriggerMarker() -> String {
        "link trigger alias works"
    }
}

extension MacroLinkedPayloadHandler.TrackedResponse {
    func macroLinkResponseMarker() -> String {
        "link response alias works"
    }
}

extension MacroLinkedTrackedHandler.TrackedTriggerEvent {
    func macroLinkTrackedTriggerMarker() -> String {
        "link tracked trigger alias works"
    }
}

extension MacroLinkedTrackedHandler.TrackedResponse {
    func macroLinkTrackedResponseMarker() -> String {
        "link tracked response alias works"
    }
}

// MARK: - Support for send / sendAndWaitForResponse coverage

/// Records handler invocations so fire-and-forget `send(...)` variants are observable in order.
actor MacroSendLog {
    private(set) var entries: [String] = []
    func append(_ entry: String) {
        entries.append(entry)
    }
}

/// A `Void`-request controller used to drive `inputEvent:`-based typed sends from inside a handler.
@RequestResponseHandlerTypes
enum MacroTypedSendController: RequestResponseTrackedBusEventHandler {
    typealias ResponsePayload = String
}

/// Serial handler so fire-and-forget request sends are processed in a deterministic order for assertions.
@RequestResponseHandlerPayloadAndTypes(request: ["message", "count"])
enum MacroSerialCaptureHandler: RequestResponseTrackedBusEventHandler {
    typealias RequestPayload = MacroSimplePayload
    typealias ResponsePayload = String
    static let concurrencyType: EventBus.ConcurrencyType = .serial
}

/// Serial observer of `MacroPayloadDrivenEvent` (a `SimpleBusEventType`) used to exercise its typed `send(...)`.
@ResponseHandlerTypes
enum MacroDrivenEventObserver: ResponseTrackedBusEventHandler {
    typealias TriggerEvent = MacroPayloadDrivenEvent
    typealias ResponsePayload = Int
    static let concurrencyType: EventBus.ConcurrencyType = .serial
}

@Suite("EventBusTests")
// swiftlint:disable:next type_body_length
struct EventBusTypeMacroIntegrationTests {
    @Test
    func simpleBusEventTypeMacroSupportsTrackedEventExtension() {
        let eventBus = EventBus()
        let trackedEvent = MacroSimpleEvent.TrackedEvent(
            busEvent: MacroSimpleEvent.event(payload: "hello"),
            eventBus: eventBus
        )

        #expect(trackedEvent.macroSimpleMarker() == "simple macro alias works")
    }

    @Test
    func busEventPayloadInitMacroAddsCanonicalPayloadInitializerHelpers() {
        let payload = MacroSimplePayload._eventBusPayloadInit(message: "hello")

        #expect(payload.message == "hello")
        #expect(payload.count == 1)
    }

    @Test
    func simpleBusEventPayloadAndTypesMacroAddsTypedEventConveniences() {
        let busEvent = MacroPayloadDrivenEvent.event(message: "hello", count: 3)

        #expect(busEvent.payload.message == "hello")
        #expect(busEvent.payload.count == 3)
    }

    @Test
    func payloadMacrosSupportUnlabeledSeparateAndKeywordInitializerLabels() {
        let payload = MacroLabeledPayload._eventBusPayloadInit(value: "default", apiValue: 1)
        #expect(payload.repeated == false)

        let event = MacroLabeledPayloadEvent.event(value: "value", apiValue: 2, repeat: true)
        #expect(event.payload.value == "value")
        #expect(event.payload.apiValue == 2)
        #expect(event.payload.repeated)
    }

    @Test
    func responseHandlerPayloadAndTypesMacroAddsTypedTriggerEventConveniences() async throws {
        let busEvent = MacroPayloadResponseHandler.event(message: "hello", count: 3)

        #expect(busEvent.payload.message == "hello")
        #expect(busEvent.payload.count == 3)

        let eventBus = EventBus()
        eventBus.register(
            handlers: [
                MacroPayloadResponseHandler.handlerRegistration { payload in
                    "\(payload.message)-\(payload.count)"
                },
            ]
        )

        let result = try await MacroPayloadResponseHandler.sendAndWaitForResponse(
            eventBus: eventBus,
            message: "hello",
            count: 3
        )

        #expect(result.busEvent.payload == "hello-3")
    }

    @Test
    func responseTrackedBusEventHandlerPayloadMacroAddsTypedTriggerEventConveniences() async throws {
        let eventBus = EventBus()
        eventBus.register(
            handlers: [
                MacroTrackedResponseHandler.handlerRegistration { inputEvent in
                    await inputEvent.appendEvent(
                        MacroTrackedResponseHandler.response(
                            payload: "\(inputEvent.busEvent.payload.message)-\(inputEvent.busEvent.payload.count)"
                        )
                    )
                },
            ]
        )

        let result = try await MacroTrackedResponseHandler.sendAndWaitForResponse(
            eventBus: eventBus,
            message: "world",
            count: 4
        )

        #expect(result.busEvent.payload == "world-4")
    }

    @Test
    func responseHandlerTypeMacroSupportsTrackedAliasExtensions() {
        let eventBus = EventBus()
        let trackedTrigger = MacroResponseHandler.TrackedTriggerEvent(
            busEvent: MacroResponseTriggerEvent.event(),
            eventBus: eventBus
        )
        let trackedResponse = MacroResponseHandler.TrackedResponse(
            busEvent: MacroResponseHandler.response(payload: "done"),
            eventBus: eventBus
        )

        #expect(trackedTrigger.macroResponseTriggerMarker() == "response trigger alias works")
        #expect(trackedResponse.macroResponseMarker() == "response alias works")
    }

    @Test
    func requestResponseHandlerTypeMacroSupportsTrackedAliasExtensions() {
        let eventBus = EventBus()
        let trackedRequest = MacroRequestResponseHandler.TrackedRequest(
            busEvent: MacroRequestResponseHandler.request(payload: "value"),
            eventBus: eventBus
        )
        let trackedResponse = MacroRequestResponseHandler.TrackedResponse(
            busEvent: MacroRequestResponseHandler.response(payload: 7),
            eventBus: eventBus
        )

        #expect(trackedRequest.macroRequestMarker() == "request alias works")
        #expect(trackedResponse.macroRequestResponseMarker() == "request response alias works")
    }

    @Test
    func requestResponseHandlerPayloadAndTypesMacroAddsTypedRequestConveniences() async throws {
        let request = MacroPayloadRequestResponseHandler.request(message: "hello", count: 5)

        #expect(request.payload.message == "hello")
        #expect(request.payload.count == 5)

        let eventBus = EventBus()
        eventBus.register(
            handlers: [
                MacroPayloadRequestResponseHandler.handlerRegistration { payload in
                    "\(payload.message)-\(payload.count)"
                },
            ]
        )

        let result = try await MacroPayloadRequestResponseHandler.sendAndWaitForResponse(
            eventBus: eventBus,
            message: "hello",
            count: 5
        )

        #expect(result.busEvent.payload == "hello-5")
    }

    @Test
    func requestResponseTrackedBusEventHandlerPayloadMacroAddsTypedRequestConveniences() async throws {
        let eventBus = EventBus()
        eventBus.register(
            handlers: [
                MacroTrackedRequestResponseHandler.handlerRegistration { inputEvent in
                    await inputEvent.appendEvent(
                        MacroTrackedRequestResponseHandler.response(
                            payload: "\(inputEvent.busEvent.payload.message)-\(inputEvent.busEvent.payload.count)"
                        )
                    )
                },
            ]
        )

        let result = try await MacroTrackedRequestResponseHandler.sendAndWaitForResponse(
            eventBus: eventBus,
            message: "world",
            count: 6
        )

        #expect(result.busEvent.payload == "world-6")
    }

    @Test
    func responseHandlerPayloadAndTypesMacroAddsTypedResponseBuilder() {
        // Trigger builder unpacks the TriggerEvent payload (message, count)...
        let triggerEvent = MacroResponseBuilderHandler.event(message: "hello", count: 3)
        #expect(triggerEvent.payload.message == "hello")
        #expect(triggerEvent.payload.count == 3)

        // ...while the response builder independently unpacks the ResponsePayload (label, score).
        let response = MacroResponseBuilderHandler.response(label: "done", score: 5)
        #expect(response.payload.label == "done")
        #expect(response.payload.score == 5)
    }

    @Test
    func requestResponseHandlerPayloadAndTypesMacroAddsTypedResponseBuilder() {
        let request = MacroRequestResponseBuilderHandler.request(message: "hello", count: 2)
        #expect(request.payload.message == "hello")
        #expect(request.payload.count == 2)

        let response = MacroRequestResponseBuilderHandler.response(label: "ok", score: 9)
        #expect(response.payload.label == "ok")
        #expect(response.payload.score == 9)
    }

    @Test
    func linkedEventHandlerPayloadAndTypesMacroAddsTypedBuilders() {
        // trigger builder unpacks the TriggerEvent payload (message, count)...
        let triggerEvent = MacroLinkedPayloadBuilderHandler.event(message: "hello", count: 4)
        #expect(triggerEvent.payload.message == "hello")
        #expect(triggerEvent.payload.count == 4)

        // ...response builder independently unpacks the ResponseEvent payload (label, score).
        let responseEvent = MacroLinkedPayloadBuilderHandler.response(label: "done", score: 7)
        #expect(responseEvent.payload.label == "done")
        #expect(responseEvent.payload.score == 7)
    }

    @Test
    func linkedEventPayloadHandlerTypeMacroSupportsTrackedAliasExtensions() {
        let eventBus = EventBus()
        let trackedTrigger = MacroLinkedPayloadHandler.TrackedTriggerEvent(
            busEvent: MacroLinkTriggerEvent.event(payload: "hello"),
            eventBus: eventBus
        )
        let trackedResponse = MacroLinkedPayloadHandler.TrackedResponse(
            busEvent: MacroLinkResponseEvent.event(payload: 7),
            eventBus: eventBus
        )

        #expect(trackedTrigger.macroLinkTriggerMarker() == "link trigger alias works")
        #expect(trackedResponse.macroLinkResponseMarker() == "link response alias works")
    }

    @Test
    func linkedTrackedBusEventHandlerTypeMacroSupportsTrackedAliasExtensions() {
        let eventBus = EventBus()
        let trackedTrigger = MacroLinkedTrackedHandler.TrackedTriggerEvent(
            busEvent: MacroLinkTrackedTriggerEvent.event(payload: 1.5),
            eventBus: eventBus
        )
        let trackedResponse = MacroLinkedTrackedHandler.TrackedResponse(
            busEvent: MacroLinkTrackedResponseEvent.event(payload: true),
            eventBus: eventBus
        )

        #expect(trackedTrigger.macroLinkTrackedTriggerMarker() == "link tracked trigger alias works")
        #expect(trackedResponse.macroLinkTrackedResponseMarker() == "link tracked response alias works")
    }

    // MARK: - Typed send / sendAndWaitForResponse coverage

    @Test
    func simpleBusEventPayloadMacroSupportsTypedSends() async throws {
        let eventBus = EventBus(defaultTimeout: .seconds(1))
        let log = MacroSendLog()
        eventBus.register(handlers: [
            MacroDrivenEventObserver.handlerRegistration { inputEvent in
                await log.append("\(inputEvent.busEvent.payload.message)-\(inputEvent.busEvent.payload.count)")
                return await inputEvent.appendEvent(
                    MacroDrivenEventObserver.response(payload: inputEvent.busEvent.payload.count)
                )
            },
            MacroTypedSendController.handlerRegistration { inputEvent in
                // typed send(inputEvent:...) — fire-and-forget from within a handler
                await MacroPayloadDrivenEvent.send(inputEvent: inputEvent, message: "fromHandler", count: 20)
                return await inputEvent.appendEvent(MacroTypedSendController.response(payload: "done"))
            },
        ])

        // typed send(eventBus:...) — fire-and-forget from the bus
        await MacroPayloadDrivenEvent.send(eventBus: eventBus, message: "fromBus", count: 10)
        _ = try await MacroTypedSendController.sendAndWaitForResponse(eventBus: eventBus)
        // serial observer guarantees prior sends are processed before this flush completes
        _ = try await MacroDrivenEventObserver.sendAndWaitForResponse(
            eventBus: eventBus,
            payload: MacroSimplePayload(message: "flush", count: 30)
        )

        let entries = await log.entries
        #expect(entries.contains("fromBus-10"))
        #expect(entries.contains("fromHandler-20"))
        #expect(entries.last == "flush-30")
    }

    @Test
    func responseHandlerPayloadMacroSupportsTypedSendAndWaitFromHandler() async throws {
        let eventBus = EventBus(defaultTimeout: .seconds(1))
        eventBus.register(handlers: [
            MacroTrackedResponseHandler.handlerRegistration { inputEvent in
                await inputEvent.appendEvent(
                    MacroTrackedResponseHandler.response(
                        payload: "\(inputEvent.busEvent.payload.message)-\(inputEvent.busEvent.payload.count)"
                    )
                )
            },
            MacroTypedSendController.handlerRegistration { inputEvent in
                // typed sendAndWaitForResponse(inputEvent:...)
                guard let downstream = try await MacroTrackedResponseHandler.sendAndWaitForResponse(
                    inputEvent: inputEvent,
                    message: "trigger",
                    count: 5
                ) else {
                    return nil
                }
                return await downstream.appendEvent(MacroTypedSendController.response(payload: downstream.busEvent.payload))
            },
        ])

        let result = try await MacroTypedSendController.sendAndWaitForResponse(eventBus: eventBus)
        #expect(result.busEvent.payload == "trigger-5")
    }

    @Test
    func requestResponseHandlerPayloadMacroSupportsTypedSendAndWaitFromHandler() async throws {
        let eventBus = EventBus(defaultTimeout: .seconds(1))
        eventBus.register(handlers: [
            MacroTrackedRequestResponseHandler.handlerRegistration { inputEvent in
                await inputEvent.appendEvent(
                    MacroTrackedRequestResponseHandler.response(
                        payload: "\(inputEvent.busEvent.payload.message)-\(inputEvent.busEvent.payload.count)"
                    )
                )
            },
            MacroTypedSendController.handlerRegistration { inputEvent in
                // typed sendAndWaitForResponse(inputEvent:...)
                guard let downstream = try await MacroTrackedRequestResponseHandler.sendAndWaitForResponse(
                    inputEvent: inputEvent,
                    message: "request",
                    count: 8
                ) else {
                    return nil
                }
                return await downstream.appendEvent(MacroTypedSendController.response(payload: downstream.busEvent.payload))
            },
        ])

        let result = try await MacroTypedSendController.sendAndWaitForResponse(eventBus: eventBus)
        #expect(result.busEvent.payload == "request-8")
    }

    @Test
    func requestResponseHandlerPayloadMacroSupportsTypedFireAndForgetSends() async throws {
        let eventBus = EventBus(defaultTimeout: .seconds(1))
        let log = MacroSendLog()
        eventBus.register(handlers: [
            MacroSerialCaptureHandler.handlerRegistration { inputEvent in
                await log.append("\(inputEvent.busEvent.payload.message)-\(inputEvent.busEvent.payload.count)")
                return await inputEvent.appendEvent(MacroSerialCaptureHandler.response(payload: "ok"))
            },
            MacroTypedSendController.handlerRegistration { inputEvent in
                // typed send(inputEvent:...) — fire-and-forget from within a handler
                await MacroSerialCaptureHandler.send(inputEvent: inputEvent, message: "fromHandler", count: 2)
                return await inputEvent.appendEvent(MacroTypedSendController.response(payload: "done"))
            },
        ])

        // typed send(eventBus:...) — fire-and-forget from the bus
        await MacroSerialCaptureHandler.send(eventBus: eventBus, message: "fromBus", count: 1)
        _ = try await MacroTypedSendController.sendAndWaitForResponse(eventBus: eventBus)
        // serial handler guarantees prior sends are processed before this flush completes
        _ = try await MacroSerialCaptureHandler.sendAndWaitForResponse(eventBus: eventBus, message: "flush", count: 3)

        let entries = await log.entries
        #expect(entries.contains("fromBus-1"))
        #expect(entries.contains("fromHandler-2"))
        #expect(entries.last == "flush-3")
    }

    @Test
    func linkedEventHandlerPayloadMacroSupportsTypedSendAndWait() async throws {
        let eventBus = EventBus(defaultTimeout: .seconds(1))
        eventBus.register(handlers: [
            MacroLinkedPayloadBuilderHandler.handlerRegistration { payload in
                MacroResponseData(label: payload.message, score: payload.count)
            },
            MacroTypedSendController.handlerRegistration { inputEvent in
                // typed sendAndWaitForResponse(inputEvent:...)
                guard let downstream = try await MacroLinkedPayloadBuilderHandler.sendAndWaitForResponse(
                    inputEvent: inputEvent,
                    message: "linked",
                    count: 3
                ) else {
                    return nil
                }
                return await downstream.appendEvent(MacroTypedSendController.response(payload: downstream.busEvent.payload.label))
            },
        ])

        // typed sendAndWaitForResponse(eventBus:...)
        let direct = try await MacroLinkedPayloadBuilderHandler.sendAndWaitForResponse(
            eventBus: eventBus,
            message: "hola",
            count: 9
        )
        #expect(direct.busEvent.payload.label == "hola")
        #expect(direct.busEvent.payload.score == 9)

        // typed sendAndWaitForResponse(inputEvent:...) via the controller
        let chained = try await MacroTypedSendController.sendAndWaitForResponse(eventBus: eventBus)
        #expect(chained.busEvent.payload == "linked")
    }
}
