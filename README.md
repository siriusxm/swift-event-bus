# `EventBus`

A shared event channel that coordinates async Swift services without coupling. The middleware layer Swift has been missing.

Once a system has multiple services that coordinate asynchronous tasks, coding every interaction through direct function calls or a web of `Combine` publishers becomes unwieldy and hard to maintain. The `EventBus` is a shared, typed event channel — a middleware layer that keeps the system maintainable. It decouples services and gives you standard tools for concurrency, ordering, cancellation, tracing, and testing.

Use the `EventBus` when asynchronous interactions between services are becoming hard to follow or test. Keep direct calls when a system is small, synchronous, and already easy to maintain.

## Features

- Strongly typed events declared as Swift protocols. Types act as routing IDs, so mismatches fail at compile time.
- Protocol extensions provide event definition/registration/sending — no manual routing tables, less boilerplate.
- Broadcast events fan out to any number of listeners — "fire and forget."
- Request-response event pairs let you call decoupled services inline with `async`/`await`.
- Declarative per-handler concurrency: `.parallel`, `.serial`, or `.restart`.
- Event history that traces multi-step workflows across nested handlers.
- Built-in timeouts and structured error propagation through async chains.
- Macros for named tracked-event types and low-boilerplate structured payload construction. See <doc:EventGuide#Integrating-Complex-Payloads>.

## Installation

Add `EventBus` with the Swift Package Manager:

```swift
dependencies: [
    .package(url: "<repository-url>", from: "<version>")
]
```

Then add `EventBus` to your target dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "EventBus", package: "EventBus")
    ]
)
```

## Quickstart

The simplest event is a broadcast or "fire and forget" event. This example system owns an `EventBus`, declares the event, and exposes a function that sends the event:

```swift
import EventBus

// Declare a type that represents your system and owns the `EventBus`, services, handlers, and event definitions.
public struct MySystem: Sendable {
    // Events are declared as types. By conforming to `SimpleBusEventType` events inherit its protocol functions.
    enum LunchTime: SimpleBusEventType {}

    // Having your system object be the single owner of `EventBus` helps manage setup and teardown as your system scales.
    private let eventBus = EventBus()

    // Your system's public API functions call the `EventBus` internally.
    public func sendLunchTime() async {
        // Events manage all their integration through reusable protocol functions.
        // So events know how to send themselves, and you do not have to maintain or match lists of event IDs.
        await LunchTime.send(eventBus: eventBus)
    }
}

let system = MySystem()
await system.sendLunchTime()
```

For a more complete example, see ``EventBusTests/EventBusExampleTests/EventBusReadMeExampleTests/readMeExample2()``

Next, add a handler for that broadcast event. The handler uses `ResponsePayloadHandler`, registers on the same bus, and responds to the `LunchTime` event by eating lunch. See <doc:EventGuide#Handler-Internals> for an overview of handler protocol types.

```swift
struct MySystem: Sendable {
    // ...
    // Introduce a decoupled service into our system.
    // Services can be kept pure of any reference to the bus or handlers, and can be injected as dependencies.
    let lunchService: LunchService

    init(lunchService: LunchService) {
        self.lunchService = lunchService
        // Attach handlers to the bus in a synchronous init function.
        // This allows clients to call APIs immediately without race conditions.
        eventBus.register(handlers: lunchHandlers)
    }
    // ...
}

// Handlers are functions that receive and process events.
// Groups of handler functions can be maintained as extensions or delegates of the system type.

extension MySystem {
    // Handlers are declared the same way as events, by conforming to protocols.
    // Note how this handler references the `LunchTime` event declared above as its `TriggerEvent`.
    // Note also it is declared as a "payload" handler though the payload defaults to `Void` so is not seen.
    enum EatLunch: ResponsePayloadHandler {
        typealias TriggerEvent = LunchTime
    }

    var lunchHandlers: [any Handlable] {
        [
            // This `handlerRegistration` function is doing a lot of integration heavy lifting.
            // It uses the triggering event's type as the event routing ID, which moves error checking to compile time.
            // Here the handler function is declared inline as a closure. You can also pass a conforming function reference.
            EatLunch.handlerRegistration {
                lunchService.eat()
            },
        ]
    }
}
```

For a more complete example, see ``EventBusTests/EventBusExampleTests/EventBusReadMeExampleTests/readMeExample3()``

Request-response event pairs wrap a decoupled API call as an inline `async`/`await` function. This example defines a `MakeGreeting` API, registers its handler, and invokes the API inline with `sendAndWaitForResponse`.

```swift
import EventBus

struct GreetingApiService: Sendable {
    // The external API would go here. Using a placeholder non-async string.
    func makeGreeting(name: String) async -> String {
        "Hello, \(name)!"
    }
}

// This example uses a delegate handler as opposed to the above example's extension.
struct GreetingHandler: Sendable {
    // Declaring the service inline for brevity. Usually you would want an injected dependency.
    let greetingApiService = GreetingApiService()

    // This protocol type declares request and response event types together with their handler function.
    // This example also introduces payloads, populated here with `String`s.
    enum MakeGreeting: RequestResponsePayloadHandler {
        typealias RequestPayload = String
        typealias ResponsePayload = String
    }

    var handlers: [any Handlable] {
        [
            // The payload handler integration unwraps the request event payload into this closure's parameter,
            // ..then takes the closure's return and automatically wraps it into a response event and sends to the bus.
            MakeGreeting.handlerRegistration { (name: String) in
                await greetingApiService.makeGreeting(name: name)
            },
        ]
    }
}

struct GreetingSystem: Sendable {
    let eventBus = EventBus()
    let greetingHandler: GreetingHandler

    init(greetingHandler: GreetingHandler) {
        self.greetingHandler = greetingHandler
        eventBus.register(handlers: greetingHandler.handlers)
    }

    func greet(_ name: String) async throws -> String {
        // Here's where the `sendAndWaitForResponse` function sends the request event and waits for the response event inline.
        // This integrates event-driven decoupling of your components with Swift's `async`/`await` processing.
        try await GreetingHandler.MakeGreeting
            .sendAndWaitForResponse(eventBus: eventBus, payload: name)
            .busEvent
            .payload
    }
}

let handler = GreetingHandler()
let system = GreetingSystem(greetingHandler: handler)
let message = try await system.greet("Sam")
```

For another example, see ``EventBusTests/EventBusExampleTests/EventBusReadMeExampleTests/readMeExample1()``

## Core Concepts

### Events

The `EventBus` defines two event primitives: `BusEvent` and `TrackedBusEvent`. To make these easier to use, the `EventBus` also defines a set of Swift protocols that automate usage of events and their handler functions. The `SimpleBusEventType`, `ResponsePayloadHandler`, and `RequestResponsePayloadHandler` from the above examples are three common protocols, and there are several other variations. For a reference organized by use case, see <doc:EventGuide#Event-Use-Case-Reference>; for a list of all protocols, see <doc:EventGuide#Event-Internals>.

### Handlers

We use the term `Handler` for both the functions that respond to `BusEvent`s and to the objects that hold those functions. The `EventBus` allows flexibility in how handler functions are integrated and organized. See <doc:EventGuide#Handler-Internals>.

### Concurrency

Each handler definition can specify how `EventBus` runs concurrent invocations:

- `.parallel` runs all invocations concurrently. This is the default.
- `.serial` queues invocations and runs one at a time.
- `.restart` cancels in-flight invocations when a newer event arrives.

See <doc:ConcurrencyTypes> for examples and selection guidance.

## Further Documentation

- <doc:EventGuide>: reference for Events and Handlers.
- <doc:EventBusVsDirectCall>: for system architecture, when to use `EventBus` events and handlers vs direct function calls.
- <doc:FactoringComplexSystems>: service and handler boundaries, `Sendable` guidance, deallocation, and weak callback patterns.
- <doc:Pipelining>: modeling multi-step async workflows as readable event pipelines.

## Project Status

`EventBus` is being prepared for open source release. Public package URL, release process, contribution policy, code of conduct, security policy, and roadmap will be added separately.

## License

`EventBus` is licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for the full text.

Copyright 2026 Sirius XM Radio LLC
