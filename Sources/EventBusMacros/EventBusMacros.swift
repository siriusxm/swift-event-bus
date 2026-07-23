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

import Foundation
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

// Macro implementations intentionally live together so shared generation helpers stay private.
// swiftlint:disable file_length

private struct EventBusMacroError: Error, CustomStringConvertible {
    let description: String
}

private struct PayloadParameterSpec {
    let externalName: String
    let localName: String
    let typeDescription: String
    let defaultValue: String?

    var metadataName: String { externalName == "_" ? localName : externalName }

    var helperParameterDeclaration: String {
        let base = "\(metadataName.sourceIdentifier): \(typeDescription)"
        return defaultValue.map { "\(base) = \($0)" } ?? base
    }

    var initializerCallArgument: String {
        externalName == "_"
            ? metadataName.sourceIdentifier
            : "\(externalName): \(metadataName.sourceIdentifier)"
    }
}

private extension FunctionParameterSyntax {
    var payloadParameterSpec: PayloadParameterSpec {
        let externalName = firstName.text.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
        let localName = (secondName?.text ?? firstName.text).trimmingCharacters(in: CharacterSet(charactersIn: "`"))

        return PayloadParameterSpec(
            externalName: externalName,
            localName: localName,
            typeDescription: type.trimmedDescription,
            defaultValue: defaultValue?.value.trimmedDescription
        )
    }
}

private extension String {
    var backtickedIfNeeded: String {
        "`\(self)`"
    }

    var sourceIdentifier: String {
        let keywords: Set<String> = [
            "as", "associatedtype", "break", "case", "catch", "class", "continue", "default", "defer",
            "deinit", "do", "else", "enum", "extension", "fallthrough", "false", "fileprivate", "for",
            "func", "guard", "if", "import", "in", "init", "inout", "internal", "is", "let", "nil",
            "open", "operator", "private", "protocol", "public", "repeat", "rethrows", "return", "self",
            "Self", "static", "struct", "subscript", "super", "switch", "throw", "throws", "true", "try",
            "typealias", "var", "where", "while",
        ]
        return keywords.contains(self) ? backtickedIfNeeded : self
    }
}

private extension InitializerDeclSyntax {
    var isSupportedEventBusPayloadInitializer: Bool {
        optionalMark == nil
            && signature.effectSpecifiers == nil
            && !signature.parameterClause.parameters.contains { parameter in
                parameter.ellipsis != nil
            }
    }

    var payloadParameterSpecs: [PayloadParameterSpec] {
        signature.parameterClause.parameters.map(\.payloadParameterSpec)
    }
}

private func metadataName(for parameterNames: [String]) -> String {
    "_EventBusPayloadInitMetadata_\(parameterNames.joined(separator: "_"))"
}

private func payloadMetadataDeclaration(for initializer: InitializerDeclSyntax) -> String {
    let parameterSpecs = initializer.payloadParameterSpecs
    let metadataTypeName = metadataName(for: parameterSpecs.map(\.metadataName))

    let typeAliases = parameterSpecs.map { parameter in
        "typealias \(parameter.metadataName.backtickedIfNeeded) = \(parameter.typeDescription)"
    }

    let defaultValues = parameterSpecs.compactMap { parameter -> String? in
        guard let defaultValue = parameter.defaultValue else {
            return nil
        }

        return "static var \("default_\(parameter.metadataName)".backtickedIfNeeded): \(parameter.metadataName.backtickedIfNeeded) { \(defaultValue) }"
    }

    let members = (typeAliases + defaultValues)
        .joined(separator: "\n\n")
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { "    \($0)" }
        .joined(separator: "\n")

    return
        """
        enum \(metadataTypeName) {
        \(members)
        }
        """
}

private func payloadInitializerHelperDeclaration(for initializer: InitializerDeclSyntax) -> String {
    let parameterSpecs = initializer.payloadParameterSpecs
    let parameterList = parameterSpecs
        .map(\.helperParameterDeclaration)
        .joined(separator: ", ")
    let payloadArguments = parameterSpecs
        .map(\.initializerCallArgument)
        .joined(separator: ", ")

    return
        """
        // swiftlint:disable:next function_parameter_count
        static func _eventBusPayloadInit(\(parameterList)) -> Self {
            Self(\(payloadArguments))
        }
        """
}

private func parameterNames(from attribute: AttributeSyntax, macroName: String) throws -> [String] {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
        return []
    }
    guard !arguments.isEmpty else {
        return []
    }

    return try arguments.map { argument in
        guard argument.label == nil else {
            throw EventBusMacroError(description: "@\(macroName) accepts only unlabeled string parameter names, like `@\(macroName)(\"query\", \"limit\")`.")
        }
        guard let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self),
              stringLiteral.segments.count == 1,
              case let .stringSegment(segment)? = stringLiteral.segments.first
        else {
            throw EventBusMacroError(description: "@\(macroName) parameters must be simple string literals.")
        }

        return segment.content.text
    }
}

private func stringLiteralValue(_ expression: ExprSyntax, macroName: String) throws -> String {
    guard let stringLiteral = expression.as(StringLiteralExprSyntax.self),
          stringLiteral.segments.count == 1,
          case let .stringSegment(segment)? = stringLiteral.segments.first
    else {
        throw EventBusMacroError(description: "@\(macroName) parameters must be simple string literals.")
    }

    return segment.content.text
}

/// Reads the string names from a labeled array-literal argument (e.g. `triggerEvent: ["x", "y"]`).
/// Returns an empty list when the label is absent, so each label is independently optional.
private func arrayParameterNames(from attribute: AttributeSyntax, label: String, macroName: String) throws -> [String] {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
          let argument = arguments.first(where: { $0.label?.text == label })
    else {
        return []
    }

    guard let array = argument.expression.as(ArrayExprSyntax.self) else {
        throw EventBusMacroError(
            description: "@\(macroName) `\(label):` must be an array literal of string names, like `\(label): [\"x\", \"y\"]`."
        )
    }

    return try array.elements.map { try stringLiteralValue($0.expression, macroName: macroName) }
}

/// Builds the typed `response(...)` convenience that unpacks the `ResponsePayload` fields, mirroring the
/// request/trigger `event(...)`/`request(...)` builders. Returns no members when no response parameters are given.
private func responsePayloadBuilder(for responseParameterNames: [String]) -> [DeclSyntax] {
    guard !responseParameterNames.isEmpty, responseParameterNames != ["payload"] else {
        return []
    }

    let metadataTypeName = metadataName(for: responseParameterNames)
    let signature = responseParameterNames
        .map { "\($0.sourceIdentifier): ResponsePayload.\(metadataTypeName).\($0.backtickedIfNeeded)" }
        .joined(separator: ", ")
    let payloadArguments = responseParameterNames
        .map { "\($0): \($0.sourceIdentifier)" }
        .joined(separator: ", ")

    return ["""
    // swiftlint:disable:next function_parameter_count
    static func response(\(raw: signature)) -> Response {
        response(payload: ResponsePayload._eventBusPayloadInit(\(raw: payloadArguments)))
    }
    """]
}

public struct SimpleBusEventTypesMacro: MemberMacro {
    public static func expansion(
        of _: AttributeSyntax,
        providingMembersOf _: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        [
            "typealias TrackedEvent = TrackedBusEvent<ObjectIdentifier, Payload>",
        ]
    }
}

public struct SimpleBusEventPayloadAndTypesMacro: MemberMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let parameterNames = try parameterNames(from: attribute, macroName: "SimpleBusEventPayloadAndTypes")
        let payloadTypeAlias = declaration.memberBlock.members
            .compactMap { $0.decl.as(TypeAliasDeclSyntax.self) }
            .first(where: { $0.name.text == "Payload" })

        guard payloadTypeAlias != nil else {
            throw EventBusMacroError(description: "@SimpleBusEventPayloadAndTypes requires a `typealias Payload = ...` declaration.")
        }

        let trackedEventAlias: DeclSyntax = "typealias TrackedEvent = TrackedBusEvent<ObjectIdentifier, Payload>"
        guard !parameterNames.isEmpty else {
            return [trackedEventAlias]
        }
        guard parameterNames != ["payload"] else {
            return [trackedEventAlias]
        }

        let metadataTypeName = metadataName(for: parameterNames)
        let signature = parameterNames
            .map { parameterName in
                let typeReference = "Payload.\(metadataTypeName).\(parameterName.backtickedIfNeeded)"
                return "\(parameterName.sourceIdentifier): \(typeReference)"
            }
            .joined(separator: ", ")
        let payloadArguments = parameterNames
            .map { "\($0): \($0.sourceIdentifier)" }
            .joined(separator: ", ")

        return [
            trackedEventAlias,
            """
            // swiftlint:disable:next function_parameter_count
            static func event(\(raw: signature)) -> Event {
                event(payload: Payload._eventBusPayloadInit(\(raw: payloadArguments)))
            }
            """,
            """
            // swiftlint:disable:next function_parameter_count
            static func send(inputEvent: AnyTrackedBusEventType, \(raw: signature)) async {
                await send(inputEvent: inputEvent, payload: Payload._eventBusPayloadInit(\(raw: payloadArguments)))
            }
            """,
            """
            // swiftlint:disable:next function_parameter_count
            static func send(eventBus: EventBus, \(raw: signature)) async {
                await send(eventBus: eventBus, payload: Payload._eventBusPayloadInit(\(raw: payloadArguments)))
            }
            """,
        ]
    }
}

public struct BusEventPayloadInitMacro: PeerMacro {
    public static func expansion(
        of _: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let initializer = declaration.as(InitializerDeclSyntax.self),
              initializer.isSupportedEventBusPayloadInitializer
        else {
            throw EventBusMacroError(
                description: "@BusEventPayloadInit requires a non-async, non-throwing, non-failable initializer with no variadic parameters."
            )
        }

        return [
            DeclSyntax(stringLiteral: payloadMetadataDeclaration(for: initializer)),
            DeclSyntax(stringLiteral: payloadInitializerHelperDeclaration(for: initializer)),
        ]
    }
}

public struct ResponseHandlerPayloadAndTypesMacro: MemberMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let triggerParameterNames = try arrayParameterNames(from: attribute, label: "triggerEvent", macroName: "ResponseHandlerPayloadAndTypes")
        let responseParameterNames = try arrayParameterNames(from: attribute, label: "response", macroName: "ResponseHandlerPayloadAndTypes")
        let trackedTriggerAlias: DeclSyntax = "typealias TrackedTriggerEvent = TrackedBusEvent<ObjectIdentifier, TriggerEventPayload>"
        let trackedResponseAlias: DeclSyntax = "typealias TrackedResponse = TrackedBusEvent<ObjectIdentifier, ResponsePayload>"

        var members: [DeclSyntax] = [trackedTriggerAlias, trackedResponseAlias]

        if !triggerParameterNames.isEmpty, triggerParameterNames != ["payload"] {
            let metadataTypeName = metadataName(for: triggerParameterNames)
            let signature = triggerParameterNames
                .map { "\($0.sourceIdentifier): TriggerEventPayload.\(metadataTypeName).\($0.backtickedIfNeeded)" }
                .joined(separator: ", ")
            let payloadArguments = triggerParameterNames
                .map { "\($0): \($0.sourceIdentifier)" }
                .joined(separator: ", ")

            members.append("""
            // swiftlint:disable:next function_parameter_count
            static func event(\(raw: signature)) -> TriggerEvent.Event {
                event(payload: TriggerEventPayload._eventBusPayloadInit(\(raw: payloadArguments)))
            }
            """)
            members.append("""
            // swiftlint:disable:next function_parameter_count
            static func sendAndWaitForResponse(
                inputEvent: AnyTrackedBusEventType,
                \(raw: signature),
                timeout: Duration? = nil
            ) async throws -> TrackedResponse? {
                try await sendAndWaitForResponse(
                    inputEvent: inputEvent,
                    payload: TriggerEventPayload._eventBusPayloadInit(\(raw: payloadArguments)),
                    timeout: timeout
                )
            }
            """)
            members.append("""
            // swiftlint:disable:next function_parameter_count
            static func sendAndWaitForResponse(
                eventBus: EventBus,
                \(raw: signature),
                timeout: Duration? = nil
            ) async throws -> TrackedResponse {
                try await sendAndWaitForResponse(
                    eventBus: eventBus,
                    payload: TriggerEventPayload._eventBusPayloadInit(\(raw: payloadArguments)),
                    timeout: timeout
                )
            }
            """)
        }

        members.append(contentsOf: responsePayloadBuilder(for: responseParameterNames))

        return members
    }
}

// Name mirrors the public macro declaration.
// swiftlint:disable:next type_name
public struct RequestResponseHandlerPayloadAndTypesMacro: MemberMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf _: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let requestParameterNames = try arrayParameterNames(from: attribute, label: "request", macroName: "RequestResponseHandlerPayloadAndTypes")
        let responseParameterNames = try arrayParameterNames(from: attribute, label: "response", macroName: "RequestResponseHandlerPayloadAndTypes")
        let trackedRequestAlias: DeclSyntax = "typealias TrackedRequest = TrackedBusEvent<ObjectIdentifier, RequestPayload>"
        let trackedResponseAlias: DeclSyntax = "typealias TrackedResponse = TrackedBusEvent<ObjectIdentifier, ResponsePayload>"

        var members: [DeclSyntax] = [trackedRequestAlias, trackedResponseAlias]

        if !requestParameterNames.isEmpty, requestParameterNames != ["payload"] {
            let metadataTypeName = metadataName(for: requestParameterNames)
            let signature = requestParameterNames
                .map { "\($0.sourceIdentifier): RequestPayload.\(metadataTypeName).\($0.backtickedIfNeeded)" }
                .joined(separator: ", ")
            let payloadArguments = requestParameterNames
                .map { "\($0): \($0.sourceIdentifier)" }
                .joined(separator: ", ")

            members.append("""
            // swiftlint:disable:next function_parameter_count
            static func request(\(raw: signature)) -> Request {
                request(payload: RequestPayload._eventBusPayloadInit(\(raw: payloadArguments)))
            }
            """)
            members.append("""
            // swiftlint:disable:next function_parameter_count
            static func send(inputEvent: AnyTrackedBusEventType, \(raw: signature)) async {
                await send(inputEvent: inputEvent, payload: RequestPayload._eventBusPayloadInit(\(raw: payloadArguments)))
            }
            """)
            members.append("""
            // swiftlint:disable:next function_parameter_count
            static func send(eventBus: EventBus, \(raw: signature)) async {
                await send(eventBus: eventBus, payload: RequestPayload._eventBusPayloadInit(\(raw: payloadArguments)))
            }
            """)
            members.append("""
            // swiftlint:disable:next function_parameter_count
            static func sendAndWaitForResponse(
                inputEvent: AnyTrackedBusEventType,
                \(raw: signature),
                timeout: Duration? = nil
            ) async throws -> TrackedResponse? {
                try await sendAndWaitForResponse(
                    inputEvent: inputEvent,
                    payload: RequestPayload._eventBusPayloadInit(\(raw: payloadArguments)),
                    timeout: timeout
                )
            }
            """)
            members.append("""
            // swiftlint:disable:next function_parameter_count
            static func sendAndWaitForResponse(
                eventBus: EventBus,
                \(raw: signature),
                timeout: Duration? = nil
            ) async throws -> TrackedResponse {
                try await sendAndWaitForResponse(
                    eventBus: eventBus,
                    payload: RequestPayload._eventBusPayloadInit(\(raw: payloadArguments)),
                    timeout: timeout
                )
            }
            """)
        }

        members.append(contentsOf: responsePayloadBuilder(for: responseParameterNames))

        return members
    }
}

public struct ResponseHandlerTypesMacro: MemberMacro {
    public static func expansion(
        of _: AttributeSyntax,
        providingMembersOf _: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        [
            "typealias TrackedTriggerEvent = TrackedBusEvent<ObjectIdentifier, TriggerEventPayload>",
            "typealias TrackedResponse = TrackedBusEvent<ObjectIdentifier, ResponsePayload>",
        ]
    }
}

public struct RequestResponseHandlerTypesMacro: MemberMacro {
    public static func expansion(
        of _: AttributeSyntax,
        providingMembersOf _: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        [
            "typealias TrackedRequest = TrackedBusEvent<ObjectIdentifier, RequestPayload>",
            "typealias TrackedResponse = TrackedBusEvent<ObjectIdentifier, ResponsePayload>",
        ]
    }
}

public struct LinkedEventHandlerTypesMacro: MemberMacro {
    public static func expansion(
        of _: AttributeSyntax,
        providingMembersOf _: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        [
            "typealias TrackedTriggerEvent = TrackedBusEvent<ObjectIdentifier, TriggerEventPayload>",
            "typealias TrackedResponse = TrackedBusEvent<ObjectIdentifier, ResponseEvent.Payload>",
        ]
    }
}

public struct LinkedEventHandlerPayloadAndTypesMacro: MemberMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf _: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let triggerParameterNames = try arrayParameterNames(from: attribute, label: "triggerEvent", macroName: "LinkedEventHandlerPayloadAndTypes")
        let responseParameterNames = try arrayParameterNames(from: attribute, label: "response", macroName: "LinkedEventHandlerPayloadAndTypes")

        var members: [DeclSyntax] = [
            "typealias TrackedTriggerEvent = TrackedBusEvent<ObjectIdentifier, TriggerEventPayload>",
            "typealias TrackedResponse = TrackedBusEvent<ObjectIdentifier, ResponseEvent.Payload>",
        ]

        if !triggerParameterNames.isEmpty, triggerParameterNames != ["payload"] {
            let metadataTypeName = metadataName(for: triggerParameterNames)
            let signature = triggerParameterNames
                .map { "\($0.sourceIdentifier): TriggerEventPayload.\(metadataTypeName).\($0.backtickedIfNeeded)" }
                .joined(separator: ", ")
            let payloadArguments = triggerParameterNames
                .map { "\($0): \($0.sourceIdentifier)" }
                .joined(separator: ", ")

            members.append("""
            // swiftlint:disable:next function_parameter_count
            static func event(\(raw: signature)) -> TriggerEvent.Event {
                TriggerEvent.event(payload: TriggerEventPayload._eventBusPayloadInit(\(raw: payloadArguments)))
            }
            """)
            members.append("""
            // swiftlint:disable:next function_parameter_count
            static func sendAndWaitForResponse(
                inputEvent: AnyTrackedBusEventType,
                \(raw: signature),
                timeout: Duration? = nil
            ) async throws -> TrackedResponse? {
                try await sendAndWaitForResponse(
                    inputEvent: inputEvent,
                    payload: TriggerEventPayload._eventBusPayloadInit(\(raw: payloadArguments)),
                    timeout: timeout
                )
            }
            """)
            members.append("""
            // swiftlint:disable:next function_parameter_count
            static func sendAndWaitForResponse(
                eventBus: EventBus,
                \(raw: signature),
                timeout: Duration? = nil
            ) async throws -> TrackedResponse {
                try await sendAndWaitForResponse(
                    eventBus: eventBus,
                    payload: TriggerEventPayload._eventBusPayloadInit(\(raw: payloadArguments)),
                    timeout: timeout
                )
            }
            """)
        }

        if !responseParameterNames.isEmpty, responseParameterNames != ["payload"] {
            let metadataTypeName = metadataName(for: responseParameterNames)
            let signature = responseParameterNames
                .map { "\($0.sourceIdentifier): ResponseEvent.Payload.\(metadataTypeName).\($0.backtickedIfNeeded)" }
                .joined(separator: ", ")
            let payloadArguments = responseParameterNames
                .map { "\($0): \($0.sourceIdentifier)" }
                .joined(separator: ", ")

            members.append("""
            // swiftlint:disable:next function_parameter_count
            static func response(\(raw: signature)) -> ResponseEvent.Event {
                ResponseEvent.event(payload: ResponseEvent.Payload._eventBusPayloadInit(\(raw: payloadArguments)))
            }
            """)
        }

        return members
    }
}

@main
struct EventBusMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        SimpleBusEventTypesMacro.self,
        SimpleBusEventPayloadAndTypesMacro.self,
        BusEventPayloadInitMacro.self,
        ResponseHandlerPayloadAndTypesMacro.self,
        ResponseHandlerTypesMacro.self,
        RequestResponseHandlerPayloadAndTypesMacro.self,
        RequestResponseHandlerTypesMacro.self,
        LinkedEventHandlerTypesMacro.self,
        LinkedEventHandlerPayloadAndTypesMacro.self,
    ]
}
