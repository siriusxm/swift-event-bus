# Event Guide

## Overview

Currently, the `EventBus` implements two common event-driven paradigms:

- Broadcast or "fire and forget" events, where a sender publishes that something happened without waiting for a response.
- Request-response event pairs, where a sender waits for a specific typed response using `async`/`await`.

The `EventBus` also supports two types of handler functions you can register to handle events:

- `Payload` handlers, which take the incoming event's payload as their parameter, and the response event's payload as their return.
- `TrackedBusEvent` handlers, which take the entire incoming event as their parameter and can make callbacks into the `EventBus` and chain the resulting events together as their response.

The primitives are designed to support additional event models as requirements evolve.

## Event Use Case Reference

Note that any event can be defined with a `Payload`, and payload types can be arbitrarily complex as long as they remain `Sendable`. `Payload`s are `Void` by default, and examples here are simplified by omitting explicit `Payload`s, except where demonstrating `Payload` integration.

### Originating or Triggering Events

It is a common requirement to have actions in your system triggered by external or independent systems that originate events. Examples are clocks and timers, sensors, and specific iOS systems such as `UIApplication`, `NotificationCenter`, `AVPlayer`, `CoreMotion`, and `StoreKit`. If you want to model these events as independent triggers decoupled from the context-specific APIs they invoke in your application, use `SimpleBusEventType`. `SimpleBusEventType` declares a reusable event that is not tied to a specific handler. This gives your system flexibility to have zero, one, or many internal observers independently reacting to these events.

```swift
enum LunchTime: SimpleBusEventType {}
enum AVPlayerDidPlayToEndTime: SimpleBusEventType {}
enum NotificationCenterAppBackgrounded: SimpleBusEventType {}
```

It is a best practice to have one object that owns a single strong reference to the `EventBus`. When events originate from within that object, you can use the `EventBus` reference directly to send these events. For examples of how to tie external systems or sub-components back to the `EventBus` so they can send events without retaining a strong `EventBus` reference, see <doc:FactoringComplexSystems#Weak-EventBus-References>.

```swift
    await LunchTime.send(eventBus: eventBus)
```

### System Entry Point Handlers

For the system to respond to external triggering events, the `EventBus` provides `ResponseHandler` protocols. These reference a `TriggerEvent` that is defined elsewhere, allow the component to define a handler function to respond to that event, and automatically define a `ResponseEvent` to return the handler's result into the `EventBus`. There are two specific `ResponseHandler` protocols: `ResponsePayloadHandler` and `ResponseTrackedBusEventHandler`.

`ResponsePayloadHandler` responds to a triggering event and automatically unwraps the triggering event's payload into the handler function's parameter, then wraps the handler function's result into a response event and automatically sends it. Use this for simple endpoint handlers that call service functions, but do not trigger nested event flows.

```swift
enum LunchTime: SimpleBusEventType {
    typealias Payload = Date
}

enum EatLunch: ResponsePayloadHandler {
    typealias TriggerEvent = LunchTime
    typealias ResponsePayload = String
}

let lunchHandlers: [any Handlable] = [
    EatLunch.handlerRegistration { (lunchTime: Date) in
        lunchService.eat(lunchTime)
        return "Yum!"
    }
]

```

For an example using a `Void` payload, see ``EventBusTests/EventBusExampleTests/EventBusReadMeExampleTests/readMeExample2()``

`ResponseTrackedBusEventHandler` is the same as `ResponsePayloadHandler` except it passes the triggering event directly to the handler function as a `TrackedBusEvent`, allowing the handler to call back into the `EventBus` API and send nested events and manipulate their results into event history without retaining a strong `EventBus` reference.

```swift
enum LunchTime: SimpleBusEventType {
    typealias Payload = LunchPreferences
}

enum OrderAndEatLunch: ResponseTrackedBusEventHandler {
    typealias TriggerEvent = LunchTime
    typealias ResponsePayload = LunchCritique
}

func orderAndEatLunch(inputEvent: LunchTime.TrackedEvent) async throws -> OrderAndEatLunch.TrackedEvent? {
    return try await inputEvent.selectColor()?
        .selectFood()?
        .eatLunch()?
        .writeCritique()
}

let lunchHandlers: [any Handlable] = [
    OrderAndEatLunch.handlerRegistration(orderAndEatLunch)
]

```

For examples of nested events sent from a `TrackedBusEventHandler`, see ``EventBusTests/EventBusExampleTests/EventBusReadMeExampleTests/readMeExample4()``

The above example implements the handler function using event pipelining. For further examples of best practices using pipelining in `TrackedBusEventHandler`s, see <doc:Pipelining>.

### Internal Component Endpoint API Events

Another common use case when modeling systems is to have internal components that implement API endpoints for server APIs or internal subsystems. For these cases, you'll most commonly want to model the events and their handlers so they look to users like a function call and can be called inline with `sendAndWaitForResponse` utilities. These are implemented with `RequestResponseHandler`s that automatically define related request and response events and their handler integration. Similar to `ResponseHandler` protocols presented above, there are two specific `RequestResponseHandler` protocols: `RequestResponsePayloadHandler` and `RequestResponseTrackedBusEventHandler`.

```swift
struct ColoredFoodService: Sendable {
    enum ColoredFoodDelivery: RequestResponsePayloadHandler {
        typealias ResponsePayload = String
    }

    let handlers: [any Handlable] = [ColoredFoodDelivery.handlerRegistration { "Green eggs and ham" }]
}

let foodResponse = try await ColoredFoodService.ColoredFoodDelivery.sendAndWaitForResponse(eventBus: eventBus)
let myGreenEggsAndHam = foodResponse.busEvent.payload
```

For the complete example, see: ``EventBusTests/EventBusExampleTests/EventBusReadMeExampleTests/readMeExample4()``

### Public API Events

The system that owns the `EventBus` will often have a public API that it offers to its clients. It is a best practice to have an object that represents the system, owns the `EventBus`, and holds all components as delegates or extensions. This way the system object can manage concurrency issues in setup and teardown and avoid retention cycles.

If your API mutates state, design the functions to return only after that state has settled completely. Production code that listens for state changes may not notice the difference, but integration tests get flaky when API functions return before their effects can be asserted.

The following example uses `RequestResponseTrackedBusEventHandler` for the outer API function.

```swift
struct LunchSystem: Sendable {
    enum EatLunchNow: RequestResponseTrackedBusEventHandler {
        typealias ResponsePayload = String
    }

    let eventBus = EventBus()
    let coloredFoodHandler: ColoredFoodHandler
    let samLunchHandler: SamLunchHandler
    let stateService: StateService

    init(
        coloredFoodHandler: ColoredFoodHandler,
        samLunchHandler: SamLunchHandler,
        stateService: StateService
    ) {
        self.coloredFoodHandler = coloredFoodHandler
        self.samLunchHandler = samLunchHandler
        self.stateService = stateService
        eventBus.register(handlers: coloredFoodHandler.handlers + samLunchHandler.handlers + handlers)
    }

    var handlers: [any Handlable] {
        [
            EatLunchNow.handlerRegistration { [stateService] inputEvent in
                guard let foodResponse = try await ColoredFoodHandler.GetColoredFood
                    .sendAndWaitForResponse(inputEvent: inputEvent)
                else {
                    return nil
                }

                guard let lunchResponse = try await SamLunchHandler.EatLunch
                    .sendAndWaitForResponse(inputEvent: foodResponse, payload: foodResponse.busEvent.payload)
                else {
                    return nil
                }

                await stateService.lunchResults(date: Date(), lunchResult: lunchResponse.busEvent.payload)
                return await lunchResponse.appendEvent(
                    EatLunchNow.response(payload: lunchResponse.busEvent.payload)
                )
            },
        ]
    }

    func eatLunchNow() async throws -> String {
        try await EatLunchNow.sendAndWaitForResponse(eventBus: eventBus).busEvent.payload
    }
}

let lunchResult = try await lunchSystem.eatLunchNow()
```

For the complete example, see: ``EventBusTests/EventBusExampleTests/EventBusReadMeExampleTests/readMeExample5()``

### Reusing Response Payloads and Events

Some components have structured responses that are reused in the component API. If the different API functions have different semantics, such that the component's clients want to differentiate which API function was called even when the results look similar, then the `ResponseHandler` and `RequestResponseHandler` protocols fit well as described in examples above. You can express any similarity in the responses by sharing payloads.

```swift
struct CommonCustomerData {
    let name: String
    let phoneNumber: String
}

struct DinnerCustomerData {
    let commonCustomerData: CommonCustomerData
    let dinnerAttire: DinnerAttire
}

enum CustomerBreakfast: RequestResponsePayloadHandler {
    typealias ResponsePayload = CommonCustomerData
}

enum CustomerLunch: ResponsePayloadHandler {
    typealias TriggerEvent = LunchTime
    typealias ResponsePayload = CommonCustomerData
}

enum CustomerDinner: RequestResponsePayloadHandler {
    typealias ResponsePayload = DinnerCustomerData
}

```

Sometimes you'll model a component that handles different incoming events but produces results that not only have the same structure, but are processed with a shared downstream function by clients and observers. An example is an analytics component that listens for different events, but produces the same analytics record for all of them, and all these records are processed the same way. In cases like this, you can reduce redundant integration code by reusing the response event across different handlers. For these cases, define the common response with a `SimpleBusEventType` and the handlers using `LinkedEventPayloadHandler`.

```swift

enum ReportResponse: SimpleBusEventType {
    typealias Payload = ReportPayload
}

enum ReportCustomerBreakfast: LinkedEventPayloadHandler {
    typealias TriggerEvent = CustomerBreakfast.ResponseEvent
    typealias ResponseEvent = ReportResponse
}

enum ReportCustomerLunch: LinkedEventPayloadHandler {
    typealias TriggerEvent = CustomerLunch.ResponseEvent
    typealias ResponseEvent = ReportResponse
}

enum ReportCustomerDinner: LinkedEventPayloadHandler {
    typealias TriggerEvent = CustomerDinner.ResponseEvent
    typealias ResponseEvent = ReportResponse
}
```

There is also a `LinkedTrackedBusEventHandler` if your component has more complex nested event processes rather than simple, single functions you would implement with payload handlers.

### Decoupled Internal Observers

There are many options for expressing your processes with event flows. One option to explore is whether to have your controller/orchestrator handler functions explicitly send events to all involved components, or whether to have some components observe the process events and react without the controller/orchestrator being aware of the interaction. Each approach has its merits and drawbacks. If you decide an interaction is better modeled with an observer, use the `ResponseHandler` protocols if the observer's processing of each event should be modeled as unique, or `LinkedEventPayloadHandler` to reuse the observer's event responses (see above).

```swift
struct SamsMotherHandler: Sendable {
    enum CheckOnSamsLunch: ResponsePayloadHandler {
        typealias TriggerEvent = SamLunchHandler.EatLunch.ResponseEvent
        typealias ResponsePayload = String
    }

    let samsMotherService: SamsMotherService

    var handlers: [any Handlable] {
        [
            CheckOnSamsLunch.handlerRegistration { [samsMotherService] lunchResult in
                await samsMotherService.judgeLunchResult(lunchResult)
            },
        ]
    }
}

```

For the complete example, see: ``EventBusTests/EventBusExampleTests/EventBusReadMeExampleTests/readMeExample6()``

### Testing Side Effect Events

There is one more protocol type we haven't mentioned yet, which is `SimpleBusEventLink`. It allows you to pick two events from the same process, send one, and wait for the other, without defining any handlers or processing for the events. It is useful for corner cases and tests related to already-defined processes, when you want to invoke a process with one event, but wait for an intermediate or side-effect event rather than the final event in the process.

```swift
enum LunchObserverTestLink: SimpleBusEventLink {
    typealias TriggerEvent = LunchSystem.EatLunchNow.RequestEvent
    typealias ResponseEvent = SamsMotherHandler.CheckOnSamsLunch
}

let observerResult = try await LunchObserverTestLink.sendAndWaitForResponse(eventBus: lunchSystem.eventBus)
```

For the complete example, see: ``EventBusTests/EventBusExampleTests/EventBusReadMeExampleTests/readMeExample6()``

For more discussion and examples, see <doc:Pipelining#Main-Events-And-Side-Effects>.


## Event Internals

The `EventBus` defines two event primitives. First, `BusEvent`s are lightweight, `Sendable` values that hold an `eventType` as a routing ID and a `payload` of user-defined data. Anyone with access to an `EventBus` can create a `BusEvent` and send it into the bus.

Second, when an event is sent, the `EventBus` wraps it in a similar type with a unique sequence index, routing history, and a weak back-reference to the bus. This wrapper is called a `TrackedBusEvent`. Callers can use a `TrackedBusEvent` to spawn related events that share routing history, or to access the `EventBus` back-reference. Only the `EventBus` can create a `TrackedBusEvent` so it can wire all its data correctly. This is mostly done internally in sending and handling functions. But the `EventBus` also exposes an `appendEvent` function to allow users to manually chain a regular `BusEvent` into a `TrackedBusEvent`'s history. See ``EventBusTests/EventBusExampleTests/EventBusReadMeExampleTests/readMeExample4()``

The primitives are deliberately low-level and flexible so the `EventBus` can support many event paradigms. But using them directly puts the integration work on you. You maintain your own event routing IDs and match them by hand across event definition, handler registration, and event sending. The result: added boilerplate, cut-and-paste errors, and bugs that don't surface until runtime.

For a manual routing example using primitive `BusEvent`s, `EventBus.add`, and `sendAndWaitForMatchingResult`, see ``EventBusTests/EventBusDeepExampleTests/EventBusDeepExampleTestsManualBusEvents/manualBusEventIntegration()``

The `EventBus` provides a better alternative in a layer of Swift protocols that use the event's type directly as its routing ID and implement the integration wiring as reusable protocol extension functions that eliminate boilerplate and move most error discovery to compile time. Currently available protocols are:

- `SimpleBusEventType` declares a reusable event that is not tied to a specific handler.
- `ResponsePayloadHandler` responds to a triggering event, unwraps the triggering event's payload into the handler function's parameter, wraps the handler function's result into a response event, and sends that response into the `EventBus`.
- `ResponseTrackedBusEventHandler` works like `ResponsePayloadHandler`, but passes the triggering event directly to the handler function as a `TrackedBusEvent` so the handler can call back into the `EventBus`, send nested events, and manipulate their results into event history without retaining a strong `EventBus` reference.
- `RequestResponsePayloadHandler` declares a request event and its matching response event in a single declaration, then integrates its payload with the correct events similarly to `ResponsePayloadHandler`.
- `RequestResponseTrackedBusEventHandler` works like `RequestResponsePayloadHandler`, but integrates the entire `TrackedBusEvent` rather than just the payload.
- `SimpleBusEventLink` allows a caller to send any existing event and wait for any other event. This is useful for testing, or for sending an event and waiting for a side-effect event rather than the defined response.
- `LinkedEventPayloadHandler` works like `RequestResponsePayloadHandler`, but allows references to any two externally defined events as the request and response. This is useful for reusing response events across related handlers.
- `LinkedTrackedBusEventHandler` works like `LinkedEventPayloadHandler`, but integrates the entire `TrackedBusEvent` rather than just the payload.

## Handler Internals

We use the term `Handler` for both the functions that respond to `BusEvent`s and to the objects that hold those functions.

### Handler Objects
The `EventBus` allows any type of object to be used to hold handler functions, from a formally defined type or extension to a loose collection of functions in an array. The only restriction is that everything that is attached to the bus, even indirectly, must be `Sendable`. See <doc:FactoringComplexSystems#Everything-is-Sendable>. Handler objects can be stateless or stateful, actor-isolated, lock-isolated, immutable or absent entirely as best fits your application. Simple services can be implemented directly in handler types. But as a system scales it quickly becomes advantageous to split services from handlers and just narrow the handler types to manage events and `EventBus` integration, using short handler functions that delegate to service functions to do the detail work. See <doc:FactoringComplexSystems#Services-And-Handlers>.

### Handler Functions and Closures

Handlers are `async` functions or closures you register with the `EventBus`. Like the event types, the handler primitives `Handler` and `TrackedBusEventHandler` are deliberately low-level for flexibility. But using them directly means more integration boilerplate in your code. The event protocols do this integration for you, which leaves your handler functions simpler and easier to maintain.

Across all the `EventBus` protocol definitions, there are two kinds of handlers. Payload handlers receive only the event payload and return only the response payload. `TrackedBusEvent` handlers receive the full tracked event, which gives them access to the event chain and a weak callback into the bus.

`ResponsePayloadHandler`, `RequestResponsePayloadHandler`, and `LinkedEventPayloadHandler` are the protocols that define payload handler functions as follows:

```swift
typealias HandlerType = @Sendable (RequestPayload) async throws -> ResponsePayload
```

Payload handler integration in the protocol extensions does a lot of heavy lifting to simplify handler functions. The protocol extension extracts the payload from the event that triggered the handler and passes it into the function as its parameter. Then when the function returns, the protocol extension takes its result, dynamically creates a response event populated with the result as its `ResponsePayload` and automatically sends the new event into the `EventBus`.

`ResponseTrackedBusEventHandler`, `RequestResponseTrackedBusEventHandler`, and `LinkedTrackedBusEventHandler` are the protocols that define `TrackedBusEvent` handler functions as follows:

```swift
typealias HandlerType = @Sendable (TrackedRequest) async throws -> TrackedResponse?
```

`TrackedBusEventHandler` integration in the protocol extensions is simpler than for payload handlers. It simply passes the triggering event straight through to the handler function, and sends the result event back into the bus. Having the `TrackedBusEvent` available inside the handler function gives function writers more power and flexibility to send nested events back into the bus, implement complex processes as Controllers or Orchestrators, manage event chaining and concurrency as main events or side effects in a process, or retain and share weak `EventBus` references. The price for this power is that the handler writers need to manually manage the `TrackedBusEvent` chain within the function and create a return `TrackedBusEvent`, often using the `EventBus`'s `appendEvent` function.

For examples of nested events sent from a `TrackedBusEventHandler`, see ``EventBusTests/EventBusExampleTests/EventBusReadMeExampleTests/readMeExample4()``

For further examples of best practices using pipelining in `TrackedBusEventHandler`s, see <doc:Pipelining>.

For examples of how to use weak `EventBus` references from `TrackedBusEventHandler`s, see <doc:FactoringComplexSystems#Weak-EventBus-References>.

## Logging Events

The `EventBus` provides an integrated `EventBusLogger` that you can use to help with tracing and troubleshooting. The `EventBusLogger` exposes some useful internal information about events as they are processed through the `EventBus`. For every event you define, you can individually log at any or all of the following precise points in internal processing, which are called `LogPoint`s:
- when an event enters the bus
- when an event enters a handler
- when an input event exits a handler
- when a response event is originated from a handler and is sent back into the bus
- when an error event is originated from a failed handler and is sent back into the bus

The log printouts contain the following information:
- the `LogPoint`
- the fully qualified type name of the event type
- a unique sequence index for this `LogPoint` operation
- the way the event was sent into the bus (called the `StepType`)
- the event's payload data (which is user-formatted through a closure)
- an error readout if needed
- a date/timestamp of the log

> **Logging and sensitive data:** log output, including formatted payloads, is written to the unified logging system (`os.Logger`). Message content is logged at the `.private` privacy level, so it is redacted in captured and release logs and shown only while a debugger is attached — but you should still avoid logging personal or otherwise sensitive data through `LogPoint` payload formatters. Treat the logger as a development and debugging aid.

An advantage to using the `EventBusLogger` is that all `LogPoint`s are declared in an array and configured into the `EventBus` at initialization time, so are collected in one place rather than scattered through the code. So it is easy to save off lists of `LogPoint`s for each process that can be reused when you are troubleshooting the process rather than having to be erased and re-created throughout the codebase for each debugging effort.

The sequence indices are especially useful to help debug race conditions, since they indicate the exact order in which the `LogPoint`s are executed globally across the `EventBus`, so you can see if they execute in unexpected order.

Here is an example list of `LogPoint`s used in ``EventBusTests/EventBusExampleTests/EventBusReadMeExampleTests/readMeExample4()``

```swift
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
            formatPayload: { "LunchTime event dispatched to a handler" }
        ),
        LogPoint(
            logPointType: .responded,
            eventType: MealService.MealDelivery.responseID,
            formatPayload: { (payload: String) in
                "MealDelivery responded with: \(payload)"
            }
        ),
        LogPoint(
            logPointType: .responded,
            eventType: SamService.SamLunch.responseID,
            formatPayload: { (payload: SamService.LunchRecord) in
                "Sam ate \(payload.food) with result: \(payload.result)"
            }
        ),
    ]
)
