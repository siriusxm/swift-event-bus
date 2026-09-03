# EventBus

A shared event channel that coordinates async Swift services without coupling. The middleware layer Swift has been missing.

Once a system has multiple services that coordinate asynchronous tasks, coding every interaction through direct function calls or a web of `Combine` publishers becomes unwieldy and hard to maintain. The `EventBus` is a shared, typed event channel — a middleware layer that keeps the system maintainable. It decouples services and gives you standard tools for concurrency, ordering, cancellation, tracing, and testing.

Use the `EventBus` when asynchronous interactions between services are becoming hard to follow or test. Keep direct calls when a system is small, synchronous, and already easy to maintain.

## Project links

- [EventBus website](https://siriusxm.github.io/swift-event-bus/)
- [Documentation and API reference](https://siriusxm.github.io/swift-event-bus/docs/documentation/eventbus/)
- [Release channels and supported versions](RELEASES.md)
- [Releases](https://github.com/siriusxm/swift-event-bus/releases)
- [Discussions](https://github.com/siriusxm/swift-event-bus/discussions)
- [Report a bug](https://github.com/siriusxm/swift-event-bus/issues/new?template=bug.md)
- [Request a feature](https://github.com/siriusxm/swift-event-bus/issues/new?template=feature.md)

## Features

- Strongly typed events declared as Swift protocols. Types act as routing IDs, so mismatches fail at compile time.
- Protocol extensions provide event definition/registration/sending — no manual routing tables, less boilerplate.
- Broadcast events fan out to any number of listeners — "fire and forget."
- Request-response event pairs let you call decoupled services inline with `async`/`await`.
- Declarative per-handler concurrency: `.parallel`, `.serial`, or `.restart`.
- Event history that traces multi-step workflows across nested handlers.
- Built-in timeouts and structured error propagation through async chains.
- Macros for named tracked-event types and low-boilerplate structured payload construction. See [the guide to integrating complex payloads](https://siriusxm.github.io/swift-event-bus/docs/documentation/eventbus/eventguide/#Integrating-Complex-Payloads).

## Installation

The current supported release is the `1.0.0-beta.1` public preview. Add it with an exact Swift Package Manager requirement:

```swift
dependencies: [
    .package(
        url: "https://github.com/siriusxm/swift-event-bus.git",
        exact: "1.0.0-beta.1"
    )
]
```

Then add `EventBus` to your target dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "EventBus", package: "swift-event-bus")
    ]
)
```

See [Release channels and supported versions](RELEASES.md) for the supported prerelease, future stable releases, previous supported versions, and the unsupported tip-of-tree dependency.

## Quickstart

The simplest event is a broadcast or "fire and forget" event. This example system owns an `EventBus`, declares the event, and exposes a function that sends the event:

```swift
import EventBus

// Define the system type that owns the EventBus, services, handlers,
// and event definitions.
public struct MySystem: Sendable {
    // Events are types. Conforming to SimpleBusEventType gives them
    // its protocol functions.
    enum LunchTime: SimpleBusEventType {}

    // Making the system the sole owner of EventBus helps manage
    // setup and teardown as it grows.
    private let eventBus = EventBus()

    // Public system APIs call EventBus internally.
    public func sendLunchTime() async {
        // Events manage their integration through reusable protocol functions.
        // So events send themselves, 
        // and you do not have to maintain or match lists of event IDs.
        await LunchTime.send(eventBus: eventBus)
    }
}

let system = MySystem()
await system.sendLunchTime()
```

For a more complete example, see [readMeExample2()](https://github.com/siriusxm/swift-event-bus/blob/main/Tests/EventBusTests/EventBusReadMeExampleTests.swift#L81).

Next, add a handler for that broadcast event. The handler uses `ResponsePayloadHandler`, registers on the same bus, and responds to the `LunchTime` event by eating lunch. See [Handler internals](https://siriusxm.github.io/swift-event-bus/docs/documentation/eventbus/eventguide/#Handler-Internals) for an overview of handler protocol types.

```swift
struct MySystem: Sendable {
    // ...
    // Introduce a decoupled service into our system.
    // Services stay independent of the bus and handlers 
    // and can be injected as dependencies.
    let lunchService: LunchService

    init(lunchService: LunchService) {
        self.lunchService = lunchService
        // Register handlers synchronously during initialization,
        // so clients can call APIs immediately without race conditions.
        eventBus.register(handlers: lunchHandlers)
    }
    // ...
}

// Handlers are functions that receive and process events.
// Group handler functionss in extensions or delegates of the system type.

extension MySystem {
    // Like events, handlers are types that conform to protocols.
    // This handler's TriggerEvent is the LunchTime event declared above.
    // This is a payload handler with a default Void payload which is not shown.
    enum EatLunch: ResponsePayloadHandler {
        typealias TriggerEvent = LunchTime
    }

    var lunchHandlers: [any Handlable] {
        [
            // handlerRegistration binds the handler function 
            // to its event type and routing information.
            // The triggering event type becomes the routing ID,
            // so mismatches fail at compile time.
            // This example handler is an inline closure. 
            // You can also pass a reference to a conforming function.
            EatLunch.handlerRegistration {
                lunchService.eat()
            },
        ]
    }
}
```

For a more complete example, see [readMeExample3()](https://github.com/siriusxm/swift-event-bus/blob/main/Tests/EventBusTests/EventBusReadMeExampleTests.swift#L144).

Request-response event pairs wrap a decoupled API call as an inline `async`/`await` function. This example defines a `MakeGreeting` API, registers its handler, and invokes the API inline with `sendAndWaitForResponse`.

```swift
import EventBus

struct GreetingApiService: Sendable {
    // The external API would go here; use a placeholder string for now.
    func makeGreeting(name: String) async -> String {
        "Hello, \(name)!"
    }
}

// This example uses a delegate handler rather than the extension above.
struct GreetingHandler: Sendable {
    // The inline service keeps this example brief; 
    // production code would normally inject a dependency.
    let greetingApiService = GreetingApiService()

    // This protocol ties request and response event types to a handler function.
    // This example also introduces String payloads.
    enum MakeGreeting: RequestResponsePayloadHandler {
        typealias RequestPayload = String
        typealias ResponsePayload = String
    }

    var handlers: [any Handlable] {
        [
            // The payload handler unwraps the request payload 
            // into this closure's parameter.
            // It wraps the closure's return in a response event 
            // and sends it to the bus.
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
        // sendAndWaitForResponse sends the request 
        // and waits for a response inline.
        // This combines event-driven decoupling 
        // with Swift's async/await processing.
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

For another example, see [readMeExample1()](https://github.com/siriusxm/swift-event-bus/blob/main/Tests/EventBusTests/EventBusReadMeExampleTests.swift#L27).

## Core Concepts

### Events

The `EventBus` defines two event primitives: `BusEvent` and `TrackedBusEvent`. To make these easier to use, the `EventBus` also defines a set of Swift protocols that automate usage of events and their handler functions. The `SimpleBusEventType`, `ResponsePayloadHandler`, and `RequestResponsePayloadHandler` from the above examples are three common protocols, and there are several other variations. For a reference organized by use case, see [Event use case reference](https://siriusxm.github.io/swift-event-bus/docs/documentation/eventbus/eventguide/#Event-Use-Case-Reference); for a list of all protocols, see [Event internals](https://siriusxm.github.io/swift-event-bus/docs/documentation/eventbus/eventguide/#Event-Internals).

### Handlers

We use the term `Handler` for both the functions that respond to `BusEvent`s and to the objects that hold those functions. The `EventBus` allows flexibility in how handler functions are integrated and organized. See [Handler internals](https://siriusxm.github.io/swift-event-bus/docs/documentation/eventbus/eventguide/#Handler-Internals).

### Concurrency

Each handler definition can specify how `EventBus` runs concurrent invocations:

- `.parallel` runs all invocations concurrently. This is the default.
- `.serial` queues invocations and runs one at a time.
- `.restart` cancels in-flight invocations when a newer event arrives.

See [Concurrency types](https://siriusxm.github.io/swift-event-bus/docs/documentation/eventbus/concurrencytypes/) for examples and selection guidance.

## Further Documentation

- [Event guide](https://siriusxm.github.io/swift-event-bus/docs/documentation/eventbus/eventguide/): reference for Events and Handlers.
- [EventBus vs. direct call systems](https://siriusxm.github.io/swift-event-bus/docs/documentation/eventbus/eventbusvsdirectcall/): when to use `EventBus` events and handlers vs. direct function calls.
- [Factoring complex systems with EventBus](https://siriusxm.github.io/swift-event-bus/docs/documentation/eventbus/factoringcomplexsystems/): service and handler boundaries, `Sendable` guidance, deallocation, and weak callback patterns.
- [Pipelining](https://siriusxm.github.io/swift-event-bus/docs/documentation/eventbus/pipelining/): modeling multi-step async workflows as readable event pipelines.

## Project Status

`1.0.0-beta.1` is the first public prerelease and supported preview of `EventBus`. The stable release will follow a period of public availability and evaluation. See [Release channels and supported versions](RELEASES.md).

## License

`EventBus` is licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for the full text.

Copyright 2026 Sirius XM Radio LLC
