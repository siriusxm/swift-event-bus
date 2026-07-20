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

// Expansion snapshots preserve generated formatting and intentionally keep related cases together.
// swiftlint:disable file_length

#if os(macOS)
@testable import EventBusMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

// swiftlint:disable:next type_body_length
final class EventBusTypeMacrosTests: XCTestCase {
    func testBusEventPayloadInitExpansion() {
        assertMacroExpansion(
            """
            struct ExamplePayload {
                @BusEventPayloadInit
                init(message: String, count: Int = 1) {}
            }
            """,
            expandedSource: """
            struct ExamplePayload {
                init(message: String, count: Int = 1) {}

                enum _EventBusPayloadInitMetadata_message_count {
                    typealias `message` = String

                    typealias `count` = Int

                    static var `default_count`: `count` {
                        1
                    }
                }

                // swiftlint:disable:next function_parameter_count
                static func _eventBusPayloadInit(message: String, count: Int = 1) -> Self {
                    Self(message: message, count: count)
                }
            }
            """,
            macros: [
                "BusEventPayloadInit": BusEventPayloadInitMacro.self,
            ]
        )
    }

    // Expansion snapshot preserves generated single-line convenience signatures.
    // swiftlint:disable line_length
    func testSimpleBusEventPayloadAndTypesExpansion() {
        assertMacroExpansion(
            """
            @SimpleBusEventPayloadAndTypes("message", "count")
            enum MyEvent: SimpleBusEventType {
                typealias Payload = ExamplePayload
            }
            """,
            expandedSource: """
            enum MyEvent: SimpleBusEventType {
                typealias Payload = ExamplePayload

                typealias TrackedEvent = TrackedBusEvent<ObjectIdentifier, Payload>

                // swiftlint:disable:next function_parameter_count
                static func event(message: Payload._EventBusPayloadInitMetadata_message_count.`message`, count: Payload._EventBusPayloadInitMetadata_message_count.`count`) -> Event {
                    event(payload: Payload._eventBusPayloadInit(message: message, count: count))
                }

                // swiftlint:disable:next function_parameter_count
                static func send(inputEvent: AnyTrackedBusEventType, message: Payload._EventBusPayloadInitMetadata_message_count.`message`, count: Payload._EventBusPayloadInitMetadata_message_count.`count`) async {
                    await send(inputEvent: inputEvent, payload: Payload._eventBusPayloadInit(message: message, count: count))
                }

                // swiftlint:disable:next function_parameter_count
                static func send(eventBus: EventBus, message: Payload._EventBusPayloadInitMetadata_message_count.`message`, count: Payload._EventBusPayloadInitMetadata_message_count.`count`) async {
                    await send(eventBus: eventBus, payload: Payload._eventBusPayloadInit(message: message, count: count))
                }
            }
            """,
            macros: [
                "SimpleBusEventPayloadAndTypes": SimpleBusEventPayloadAndTypesMacro.self,
            ]
        )
    }
    // swiftlint:enable line_length

    func testSimpleBusEventPayloadAndTypesSkipsDuplicatePayloadHelpers() {
        assertMacroExpansion(
            """
            @SimpleBusEventPayloadAndTypes("payload")
            enum MyEvent: SimpleBusEventType {
                typealias Payload = String
            }
            """,
            expandedSource: """
            enum MyEvent: SimpleBusEventType {
                typealias Payload = String

                typealias TrackedEvent = TrackedBusEvent<ObjectIdentifier, Payload>
            }
            """,
            macros: [
                "SimpleBusEventPayloadAndTypes": SimpleBusEventPayloadAndTypesMacro.self,
            ]
        )
    }

    func testSimpleBusEventPayloadAndTypesSkipsVoidLikeHelpers() {
        assertMacroExpansion(
            """
            @SimpleBusEventPayloadAndTypes()
            enum MyEvent: SimpleBusEventType {
                typealias Payload = Void
            }
            """,
            expandedSource: """
            enum MyEvent: SimpleBusEventType {
                typealias Payload = Void

                typealias TrackedEvent = TrackedBusEvent<ObjectIdentifier, Payload>
            }
            """,
            macros: [
                "SimpleBusEventPayloadAndTypes": SimpleBusEventPayloadAndTypesMacro.self,
            ]
        )
    }

    func testSimpleBusEventTypesExpansion() {
        assertMacroExpansion(
            """
            @SimpleBusEventTypes
            enum MyEvent: SimpleBusEventType {
                typealias Payload = String
            }
            """,
            expandedSource: """
            enum MyEvent: SimpleBusEventType {
                typealias Payload = String

                typealias TrackedEvent = TrackedBusEvent<ObjectIdentifier, Payload>
            }
            """,
            macros: [
                "SimpleBusEventTypes": SimpleBusEventTypesMacro.self,
            ]
        )
    }

    // Expansion snapshot preserves generated single-line payload parameter lists.
    // swiftlint:disable line_length
    func testResponseHandlerPayloadAndTypesExpansion() {
        assertMacroExpansion(
            """
            @ResponseHandlerPayloadAndTypes(triggerEvent: ["message", "count"])
            enum MyHandler: ResponsePayloadHandler {
                typealias TriggerEvent = ExampleTriggerEvent
                typealias ResponsePayload = String
            }
            """,
            expandedSource: """
            enum MyHandler: ResponsePayloadHandler {
                typealias TriggerEvent = ExampleTriggerEvent
                typealias ResponsePayload = String

                typealias TrackedTriggerEvent = TrackedBusEvent<ObjectIdentifier, TriggerEventPayload>

                typealias TrackedResponse = TrackedBusEvent<ObjectIdentifier, ResponsePayload>

                // swiftlint:disable:next function_parameter_count
                static func event(message: TriggerEventPayload._EventBusPayloadInitMetadata_message_count.`message`, count: TriggerEventPayload._EventBusPayloadInitMetadata_message_count.`count`) -> TriggerEvent.Event {
                    event(payload: TriggerEventPayload._eventBusPayloadInit(message: message, count: count))
                }

                // swiftlint:disable:next function_parameter_count
                static func sendAndWaitForResponse(
                    inputEvent: AnyTrackedBusEventType,
                    message: TriggerEventPayload._EventBusPayloadInitMetadata_message_count.`message`, count: TriggerEventPayload._EventBusPayloadInitMetadata_message_count.`count`,
                    timeout: Duration? = nil
                ) async throws -> TrackedResponse? {
                    try await sendAndWaitForResponse(
                        inputEvent: inputEvent,
                        payload: TriggerEventPayload._eventBusPayloadInit(message: message, count: count),
                        timeout: timeout
                    )
                }

                // swiftlint:disable:next function_parameter_count
                static func sendAndWaitForResponse(
                    eventBus: EventBus,
                    message: TriggerEventPayload._EventBusPayloadInitMetadata_message_count.`message`, count: TriggerEventPayload._EventBusPayloadInitMetadata_message_count.`count`,
                    timeout: Duration? = nil
                ) async throws -> TrackedResponse {
                    try await sendAndWaitForResponse(
                        eventBus: eventBus,
                        payload: TriggerEventPayload._eventBusPayloadInit(message: message, count: count),
                        timeout: timeout
                    )
                }
            }
            """,
            macros: [
                "ResponseHandlerPayloadAndTypes": ResponseHandlerPayloadAndTypesMacro.self,
            ]
        )
    }
    // swiftlint:enable line_length

    func testResponseHandlerTypesExpansion() {
        assertMacroExpansion(
            """
            @ResponseHandlerTypes
            enum MyHandler: ResponsePayloadHandler {
                typealias TriggerEvent = MyTriggerEvent
                typealias ResponsePayload = String
            }
            """,
            expandedSource: """
            enum MyHandler: ResponsePayloadHandler {
                typealias TriggerEvent = MyTriggerEvent
                typealias ResponsePayload = String

                typealias TrackedTriggerEvent = TrackedBusEvent<ObjectIdentifier, TriggerEventPayload>

                typealias TrackedResponse = TrackedBusEvent<ObjectIdentifier, ResponsePayload>
            }
            """,
            macros: [
                "ResponseHandlerTypes": ResponseHandlerTypesMacro.self,
            ]
        )
    }

    func testRequestResponseHandlerTypesExpansion() {
        assertMacroExpansion(
            """
            @RequestResponseHandlerTypes
            enum MyHandler: RequestResponsePayloadHandler {
                typealias RequestPayload = String
                typealias ResponsePayload = Int
            }
            """,
            expandedSource: """
            enum MyHandler: RequestResponsePayloadHandler {
                typealias RequestPayload = String
                typealias ResponsePayload = Int

                typealias TrackedRequest = TrackedBusEvent<ObjectIdentifier, RequestPayload>

                typealias TrackedResponse = TrackedBusEvent<ObjectIdentifier, ResponsePayload>
            }
            """,
            macros: [
                "RequestResponseHandlerTypes": RequestResponseHandlerTypesMacro.self,
            ]
        )
    }

    func testLinkedEventHandlerTypesExpansion() {
        assertMacroExpansion(
            """
            @LinkedEventHandlerTypes
            enum MyHandler: LinkedEventPayloadHandler {
                typealias TriggerEvent = MyTriggerEvent
                typealias ResponseEvent = MyResponseEvent
            }
            """,
            expandedSource: """
            enum MyHandler: LinkedEventPayloadHandler {
                typealias TriggerEvent = MyTriggerEvent
                typealias ResponseEvent = MyResponseEvent

                typealias TrackedTriggerEvent = TrackedBusEvent<ObjectIdentifier, TriggerEventPayload>

                typealias TrackedResponse = TrackedBusEvent<ObjectIdentifier, ResponseEvent.Payload>
            }
            """,
            macros: [
                "LinkedEventHandlerTypes": LinkedEventHandlerTypesMacro.self,
            ]
        )
    }

    // Expansion snapshot preserves generated single-line payload parameter lists.
    // swiftlint:disable line_length
    func testRequestResponseHandlerPayloadAndTypesExpansion() {
        assertMacroExpansion(
            """
            @RequestResponseHandlerPayloadAndTypes(request: ["message", "count"])
            enum MyHandler: RequestResponsePayloadHandler {
                typealias RequestPayload = ExamplePayload
                typealias ResponsePayload = Int
            }
            """,
            expandedSource: """
            enum MyHandler: RequestResponsePayloadHandler {
                typealias RequestPayload = ExamplePayload
                typealias ResponsePayload = Int

                typealias TrackedRequest = TrackedBusEvent<ObjectIdentifier, RequestPayload>

                typealias TrackedResponse = TrackedBusEvent<ObjectIdentifier, ResponsePayload>

                // swiftlint:disable:next function_parameter_count
                static func request(message: RequestPayload._EventBusPayloadInitMetadata_message_count.`message`, count: RequestPayload._EventBusPayloadInitMetadata_message_count.`count`) -> Request {
                    request(payload: RequestPayload._eventBusPayloadInit(message: message, count: count))
                }

                // swiftlint:disable:next function_parameter_count
                static func send(inputEvent: AnyTrackedBusEventType, message: RequestPayload._EventBusPayloadInitMetadata_message_count.`message`, count: RequestPayload._EventBusPayloadInitMetadata_message_count.`count`) async {
                    await send(inputEvent: inputEvent, payload: RequestPayload._eventBusPayloadInit(message: message, count: count))
                }

                // swiftlint:disable:next function_parameter_count
                static func send(eventBus: EventBus, message: RequestPayload._EventBusPayloadInitMetadata_message_count.`message`, count: RequestPayload._EventBusPayloadInitMetadata_message_count.`count`) async {
                    await send(eventBus: eventBus, payload: RequestPayload._eventBusPayloadInit(message: message, count: count))
                }

                // swiftlint:disable:next function_parameter_count
                static func sendAndWaitForResponse(
                    inputEvent: AnyTrackedBusEventType,
                    message: RequestPayload._EventBusPayloadInitMetadata_message_count.`message`, count: RequestPayload._EventBusPayloadInitMetadata_message_count.`count`,
                    timeout: Duration? = nil
                ) async throws -> TrackedResponse? {
                    try await sendAndWaitForResponse(
                        inputEvent: inputEvent,
                        payload: RequestPayload._eventBusPayloadInit(message: message, count: count),
                        timeout: timeout
                    )
                }

                // swiftlint:disable:next function_parameter_count
                static func sendAndWaitForResponse(
                    eventBus: EventBus,
                    message: RequestPayload._EventBusPayloadInitMetadata_message_count.`message`, count: RequestPayload._EventBusPayloadInitMetadata_message_count.`count`,
                    timeout: Duration? = nil
                ) async throws -> TrackedResponse {
                    try await sendAndWaitForResponse(
                        eventBus: eventBus,
                        payload: RequestPayload._eventBusPayloadInit(message: message, count: count),
                        timeout: timeout
                    )
                }
            }
            """,
            macros: [
                "RequestResponseHandlerPayloadAndTypes": RequestResponseHandlerPayloadAndTypesMacro.self,
            ]
        )
    }
    // swiftlint:enable line_length

    func testResponseHandlerPayloadAndTypesEmitsResponseBuilder() {
        assertMacroExpansion(
            """
            @ResponseHandlerPayloadAndTypes(response: ["status"])
            enum MyHandler: ResponsePayloadHandler {
                typealias TriggerEvent = MyTriggerEvent
                typealias ResponsePayload = ExampleResponse
            }
            """,
            expandedSource: """
            enum MyHandler: ResponsePayloadHandler {
                typealias TriggerEvent = MyTriggerEvent
                typealias ResponsePayload = ExampleResponse

                typealias TrackedTriggerEvent = TrackedBusEvent<ObjectIdentifier, TriggerEventPayload>

                typealias TrackedResponse = TrackedBusEvent<ObjectIdentifier, ResponsePayload>

                // swiftlint:disable:next function_parameter_count
                static func response(status: ResponsePayload._EventBusPayloadInitMetadata_status.`status`) -> Response {
                    response(payload: ResponsePayload._eventBusPayloadInit(status: status))
                }
            }
            """,
            macros: [
                "ResponseHandlerPayloadAndTypes": ResponseHandlerPayloadAndTypesMacro.self,
            ]
        )
    }

    func testRequestResponseHandlerPayloadAndTypesEmitsResponseBuilder() {
        assertMacroExpansion(
            """
            @RequestResponseHandlerPayloadAndTypes(response: ["status"])
            enum MyHandler: RequestResponsePayloadHandler {
                typealias RequestPayload = ExampleRequest
                typealias ResponsePayload = ExampleResponse
            }
            """,
            expandedSource: """
            enum MyHandler: RequestResponsePayloadHandler {
                typealias RequestPayload = ExampleRequest
                typealias ResponsePayload = ExampleResponse

                typealias TrackedRequest = TrackedBusEvent<ObjectIdentifier, RequestPayload>

                typealias TrackedResponse = TrackedBusEvent<ObjectIdentifier, ResponsePayload>

                // swiftlint:disable:next function_parameter_count
                static func response(status: ResponsePayload._EventBusPayloadInitMetadata_status.`status`) -> Response {
                    response(payload: ResponsePayload._eventBusPayloadInit(status: status))
                }
            }
            """,
            macros: [
                "RequestResponseHandlerPayloadAndTypes": RequestResponseHandlerPayloadAndTypesMacro.self,
            ]
        )
    }

    func testLinkedEventHandlerPayloadAndTypesExpansion() {
        assertMacroExpansion(
            """
            @LinkedEventHandlerPayloadAndTypes(triggerEvent: ["startTime"], response: ["summary"])
            enum ReportLunch: LinkedTrackedBusEventHandler {
                typealias TriggerEvent = LunchStarted
                typealias ResponseEvent = LunchReport
            }
            """,
            expandedSource: """
            enum ReportLunch: LinkedTrackedBusEventHandler {
                typealias TriggerEvent = LunchStarted
                typealias ResponseEvent = LunchReport

                typealias TrackedTriggerEvent = TrackedBusEvent<ObjectIdentifier, TriggerEventPayload>

                typealias TrackedResponse = TrackedBusEvent<ObjectIdentifier, ResponseEvent.Payload>

                // swiftlint:disable:next function_parameter_count
                static func event(startTime: TriggerEventPayload._EventBusPayloadInitMetadata_startTime.`startTime`) -> TriggerEvent.Event {
                    TriggerEvent.event(payload: TriggerEventPayload._eventBusPayloadInit(startTime: startTime))
                }

                // swiftlint:disable:next function_parameter_count
                static func sendAndWaitForResponse(
                    inputEvent: AnyTrackedBusEventType,
                    startTime: TriggerEventPayload._EventBusPayloadInitMetadata_startTime.`startTime`,
                    timeout: Duration? = nil
                ) async throws -> TrackedResponse? {
                    try await sendAndWaitForResponse(
                        inputEvent: inputEvent,
                        payload: TriggerEventPayload._eventBusPayloadInit(startTime: startTime),
                        timeout: timeout
                    )
                }

                // swiftlint:disable:next function_parameter_count
                static func sendAndWaitForResponse(
                    eventBus: EventBus,
                    startTime: TriggerEventPayload._EventBusPayloadInitMetadata_startTime.`startTime`,
                    timeout: Duration? = nil
                ) async throws -> TrackedResponse {
                    try await sendAndWaitForResponse(
                        eventBus: eventBus,
                        payload: TriggerEventPayload._eventBusPayloadInit(startTime: startTime),
                        timeout: timeout
                    )
                }

                // swiftlint:disable:next function_parameter_count
                static func response(summary: ResponseEvent.Payload._EventBusPayloadInitMetadata_summary.`summary`) -> ResponseEvent.Event {
                    ResponseEvent.event(payload: ResponseEvent.Payload._eventBusPayloadInit(summary: summary))
                }
            }
            """,
            macros: [
                "LinkedEventHandlerPayloadAndTypes": LinkedEventHandlerPayloadAndTypesMacro.self,
            ]
        )
    }

    func testBusEventPayloadInitSupportsInitializerLabelsAndKeywords() {
        assertMacroExpansion(
            """
            struct ExamplePayload {
                @BusEventPayloadInit
                init(_ value: String, apiValue localValue: Int, `repeat`: Bool = false) {}
            }
            """,
            expandedSource: """
            struct ExamplePayload {
                init(_ value: String, apiValue localValue: Int, `repeat`: Bool = false) {}

                enum _EventBusPayloadInitMetadata_value_apiValue_repeat {
                    typealias `value` = String

                    typealias `apiValue` = Int

                    typealias `repeat` = Bool

                    static var `default_repeat`: `repeat` {
                        false
                    }
                }

                // swiftlint:disable:next function_parameter_count
                static func _eventBusPayloadInit(value: String, apiValue: Int, `repeat`: Bool = false) -> Self {
                    Self(value, apiValue: apiValue, repeat: `repeat`)
                }
            }
            """,
            macros: [
                "BusEventPayloadInit": BusEventPayloadInitMacro.self,
            ]
        )
    }

    func testSimpleBusEventPayloadAndTypesRequiresPayloadAlias() {
        assertMacroExpansion(
            """
            @SimpleBusEventPayloadAndTypes("message")
            enum MyEvent: SimpleBusEventType {}
            """,
            expandedSource: """
            enum MyEvent: SimpleBusEventType {}
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@SimpleBusEventPayloadAndTypes requires a `typealias Payload = ...` declaration.",
                    line: 1,
                    column: 1
                ),
            ],
            macros: [
                "SimpleBusEventPayloadAndTypes": SimpleBusEventPayloadAndTypesMacro.self,
            ]
        )
    }

    // Diagnostic snapshot preserves the complete user-facing message.
    // swiftlint:disable line_length
    func testSimpleBusEventPayloadAndTypesRejectsLabeledAndNonStringArguments() {
        assertMacroExpansion(
            """
            @SimpleBusEventPayloadAndTypes(field: "message")
            enum MyEvent: SimpleBusEventType {
                typealias Payload = String
            }
            """,
            expandedSource: """
            enum MyEvent: SimpleBusEventType {
                typealias Payload = String
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@SimpleBusEventPayloadAndTypes accepts only unlabeled string parameter names, like `@SimpleBusEventPayloadAndTypes(\"query\", \"limit\")`.",
                    line: 1,
                    column: 1
                ),
            ],
            macros: [
                "SimpleBusEventPayloadAndTypes": SimpleBusEventPayloadAndTypesMacro.self,
            ]
        )

        assertMacroExpansion(
            """
            @SimpleBusEventPayloadAndTypes(42)
            enum MyEvent: SimpleBusEventType {
                typealias Payload = String
            }
            """,
            expandedSource: """
            enum MyEvent: SimpleBusEventType {
                typealias Payload = String
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@SimpleBusEventPayloadAndTypes parameters must be simple string literals.",
                    line: 1,
                    column: 1
                ),
            ],
            macros: [
                "SimpleBusEventPayloadAndTypes": SimpleBusEventPayloadAndTypesMacro.self,
            ]
        )
    }
    // swiftlint:enable line_length

    func testHandlerPayloadAndTypesRejectsNonArrayAndNonStringArguments() {
        assertMacroExpansion(
            """
            @ResponseHandlerPayloadAndTypes(triggerEvent: "message")
            enum MyHandler: ResponsePayloadHandler {}
            """,
            expandedSource: """
            enum MyHandler: ResponsePayloadHandler {}
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@ResponseHandlerPayloadAndTypes `triggerEvent:` must be an array literal of string names, like `triggerEvent: [\"x\", \"y\"]`.",
                    line: 1,
                    column: 1
                ),
            ],
            macros: [
                "ResponseHandlerPayloadAndTypes": ResponseHandlerPayloadAndTypesMacro.self,
            ]
        )

        assertMacroExpansion(
            """
            @LinkedEventHandlerPayloadAndTypes(response: [42])
            enum MyHandler: LinkedEventPayloadHandler {}
            """,
            expandedSource: """
            enum MyHandler: LinkedEventPayloadHandler {}
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@LinkedEventHandlerPayloadAndTypes parameters must be simple string literals.",
                    line: 1,
                    column: 1
                ),
            ],
            macros: [
                "LinkedEventHandlerPayloadAndTypes": LinkedEventHandlerPayloadAndTypesMacro.self,
            ]
        )
    }

    func testBusEventPayloadInitRejectsUnsupportedInitializers() {
        let message = "@BusEventPayloadInit requires a non-async, non-throwing, non-failable initializer with no variadic parameters."
        let macros = ["BusEventPayloadInit": BusEventPayloadInitMacro.self]

        for initializer in [
            "init(value: String) throws {}",
            "init(value: String) async {}",
            "init?(value: String) {}",
            "init(values: String...) {}",
        ] {
            assertMacroExpansion(
                """
                struct ExamplePayload {
                    @BusEventPayloadInit
                    \(initializer)
                }
                """,
                expandedSource: """
                struct ExamplePayload {
                    \(initializer)
                }
                """,
                diagnostics: [DiagnosticSpec(message: message, line: 2, column: 5)],
                macros: macros
            )
        }
    }

    func testPayloadHandlerMacrosSkipHelpersForEmptyAndPayloadNames() {
        assertMacroExpansion(
            """
            @ResponseHandlerPayloadAndTypes(triggerEvent: [], response: ["payload"])
            enum ResponseHandler: ResponsePayloadHandler {}

            @RequestResponseHandlerPayloadAndTypes(request: ["payload"], response: [])
            enum RequestHandler: RequestResponsePayloadHandler {}

            @LinkedEventHandlerPayloadAndTypes(triggerEvent: ["payload"], response: ["payload"])
            enum LinkedHandler: LinkedEventPayloadHandler {}
            """,
            expandedSource: """
            enum ResponseHandler: ResponsePayloadHandler {

                typealias TrackedTriggerEvent = TrackedBusEvent<ObjectIdentifier, TriggerEventPayload>

                typealias TrackedResponse = TrackedBusEvent<ObjectIdentifier, ResponsePayload>
            }
            enum RequestHandler: RequestResponsePayloadHandler {

                typealias TrackedRequest = TrackedBusEvent<ObjectIdentifier, RequestPayload>

                typealias TrackedResponse = TrackedBusEvent<ObjectIdentifier, ResponsePayload>
            }
            enum LinkedHandler: LinkedEventPayloadHandler {

                typealias TrackedTriggerEvent = TrackedBusEvent<ObjectIdentifier, TriggerEventPayload>

                typealias TrackedResponse = TrackedBusEvent<ObjectIdentifier, ResponseEvent.Payload>
            }
            """,
            macros: [
                "ResponseHandlerPayloadAndTypes": ResponseHandlerPayloadAndTypesMacro.self,
                "RequestResponseHandlerPayloadAndTypes": RequestResponseHandlerPayloadAndTypesMacro.self,
                "LinkedEventHandlerPayloadAndTypes": LinkedEventHandlerPayloadAndTypesMacro.self,
            ]
        )
    }
}
#endif
// swiftlint:enable file_length
