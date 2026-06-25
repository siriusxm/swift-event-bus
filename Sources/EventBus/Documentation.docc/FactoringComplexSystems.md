# Factoring Complex Systems With `EventBus`

## Overview
Complex systems don't organize themselves. This article describes how to factor your system with the `EventBus` so it helps manage complexity instead of adding more.

## Everything is `Sendable`
The `EventBus` and all `BusEvent`s are `Sendable`. Complex asynchronous systems can introduce race conditions, deadlocks, retention cycles, deallocation crashes, and other difficult issues. To reduce that complexity, the `EventBus` internally synchronizes its handler registration and event dispatch with lock isolation, so its API is safe to call from any concurrency context.

To satisfy Swift's strict concurrency checking without using `@unchecked Sendable`, all functions or closures registered as handlers must also be `Sendable`, and this requirement cascades to the handler and service objects that implement those functions. This provides a good baseline, but it will not prevent every concurrency or lifetime problem by itself. Keep concurrency and reference-retention issues front-of-mind as you design the system.

See ``EventBusTests/EventBusDeepExampleTests/EventBusDeepExampleTestsFactoring/everythingIsSendableExample()``

## Services And Handlers
When factoring a system to integrate with the `EventBus`, analyze each component to see which functions are synchronous or asynchronous, and which other components call those functions.

Any asynchronous function is usually a good candidate for a `BusEvent` and handler function. Asynchronous functions already carry complexity such as timeouts, cancellation, and race conditions, so event definitions add little incremental cost while making `EventBus` concurrency and tracking features uniformly available.

For synchronous functions, use judgment. Direct calls are simpler and faster, but they create direct code dependencies between caller and service. If one component calls another component's synchronous function, a direct dependency may be better. If many components call the same synchronous function, weigh whether simplifying the dependency graph is worth turning that operation into an event and handler.

API consistency is also a factor. If almost all API functions are asynchronous, it can be clearer to code them uniformly as events and handlers rather than mixing event-driven and direct-call APIs in the same service.

If you have a service that has a mixed API with some synchronous functions and some asynchronous, you should consider the possibility of the same service supporting different protocols. The synchronous protocol should be given to its callers as a code dependency and the asynchronous protocol should be implemented on the `EventBus` with `BusEvent`s and handlers.

Though the simple examples in the README have services with handler functions declared directly inside them, production-scale systems usually benefit from separating services from handlers. Services can then be isolated and tested independently, while handlers own shared data, `BusEvent` definitions, and delegation into services.

Each handler should only delegate to its own service. Having handlers reach across to other services with direct calls will re-introduce code dependencies that you are using the `EventBus` to eliminate.

A benefit of this service/handler separation is that it reinforces the best practice for your services to be defined by protocols and to be injected at initialization time into the handlers. This allows services to be tested in detail independently of the rest of the system, and service mocks easily defined for integration testing. If a service is stateful, it is another benefit to have the state data and state management separated out from the handler and isolated behind the service's protocol API.

Another benefit of service/handler separation is that it helps manage shared data definitions vs specific data parameters for each service API. If the handlers manage shared data definitions and unified formats in their payload definitions, the services can have their data definitions optimized just for their needs and rely on the handlers to narrow the passed data and translate as they delegate.

See ``EventBusTests/EventBusDeepExampleTests/EventBusDeepExampleTestsFactoring/separatingServicesAndHandlersExample()``

## Controllers, Mediators, and Orchestrators
The `EventBus` enables `TrackedBusEventHandler` functions to send events back into the bus and wait for results. This is the main feature needed by controller-related patterns such as Mediator and Orchestrator. For complex multi-step asynchronous processes, the `EventBus` can factor process-management logic out of services and into top-level controllers without creating god-object or dependency-hub anti-patterns.

To deconstruct your processes into event flows, there are several common patterns you can use, including: triggering events, request-response pairs, public/internal APIs, side effects, and observers. For detailed discussion, see <doc:EventGuide#Event-Use-Case-Reference>.

One especially useful pattern to keep `TrackedBusEventHandler` functions lightweight is to delegate all but the top-level logic to events or the controller's local service. Ideally, a handler for a ten-step process can read as ten process-level calls inside a `do`/`catch` block. See <doc:Pipelining> for examples.

## Payloads
All `BusEvent`s can include data, called payloads. `BusEvent`s can stand in for function calls, function returns, or both.

For request and triggering events, data is usually a direct pass-through to the handling service function's parameter list. But for response events, you'll often want to put more information into the payloads than you would in a direct call system. Response data is valuable for testing and troubleshooting in asynchronous systems. Complex asynchronous processes are difficult to troubleshoot because their process steps don't always happen in a predictable order, and the results of operations performed on parallel threads are often gone by the time you detect a bug.

When a payload contains a single value, whether primitive or structured, use it directly in event declarations as the payload. Don't put an extra wrapper around data just to include it in a payload. That creates extra boilerplate for creating and sending events.

See ``EventBusTests/EventBusExampleTests/EventBusReadMeExampleTests/readMeExample4()``

## `EventBus` Deallocation
The owner of an `EventBus` is usually the top-level API owner, controller, or orchestrator for the event-driven subsystem. That owner should retain one strong reference to the `EventBus` and release it when appropriate for the app or service lifecycle. When that owner releases the bus, registered handlers and services should release without retention cycles.

To make this work, neither handler nor service definitions should retain strong references to the `EventBus` in local variables or members. Following the above conventions, handlers should be lightweight adapters that capture only the service dependencies they need and delegate the real work to those services.

If the owner releases the `EventBus` while a simple top-level handler is waiting on an asynchronous service call, the `EventBus` keeps the in-flight handler operation alive long enough for the handler to return normally. After that operation exits, there should be no strong references left in the `EventBus` or any handlers or services it has been retaining with handler registration, so the `EventBus` should be able to deallocate normally. This allows service code to stay unaware of bus lifetime and avoids requiring handlers to manually break cycles.

See ``EventBusTests/EventBusDeepExampleTests/EventBusDeepExampleTestsDeallocation/singleServiceHandlerDeallocationExample()``

For edge cases covering "fire and forget" sends, thrown service errors, `.restart` handlers, and multiple parallel in-flight handlers, see ``EventBusTests/EventBusDeepExampleTests/EventBusDeallocEdgeCases/fireAndForgetHandlerDeallocationExample()``, ``EventBusTests/EventBusDeepExampleTests/EventBusDeallocEdgeCases/throwingServiceHandlerDeallocationExample()``, ``EventBusTests/EventBusDeepExampleTests/EventBusDeallocEdgeCases/restartHandlerDeallocationExample()``, and ``EventBusTests/EventBusDeepExampleTests/EventBusDeallocEdgeCases/parallelHandlersDeallocateAfterInFlightHandlersFinish()``.

The same pattern applies when a top-level Controller or Orchestrator handler sends an event to another handler and the nested handler is waiting on a service call. The nested handler can return normally, the top-level handler can receive that response and return its own response, and the `EventBus` will finish releasing itself after the in-flight chain unwinds.

See ``EventBusTests/EventBusDeepExampleTests/EventBusDeepExampleTestsDeallocation/nestedServiceHandlerDeallocationExample()``

## Weak `EventBus` References
Some subsystems start long-lived periodic work, such as timers or polling loops. When using the `EventBus`, there will be handlers associated with those systems. These handlers can start internal processes by sending events back into the `EventBus` long after any single handler function is invoked. In these cases, the handler should not retain a strong `EventBus` reference in the timer or worker object. Instead, best practice is to pass a closure that reads the weak `EventBus` callback from an initiating handler function's input event.

The timer or worker should re-check that weak reference each time it wants to send an event. If the callback is `nil`, the `EventBus` owner has released the bus and the timer should stop cleanly. This lets timer-driven code avoid retention cycles while still sending periodic events while the bus is alive.

The event handler that starts the timer should also be re-entrant. If the timer is already running, additional start events should return normally without starting a second timer.

See ``EventBusTests/EventBusDeepExampleTests/EventBusDeepExampleTestsCallback/weakEventBusTimerExample()``

Existing or external services may already own their own asynchronous work and need to call back into the system; an example is `AVPlayer` and its callbacks. In these cases, there is no event handler that controls the invocation of the work, but the external system can be wrapped in a service that a handler owns. Best practice is to keep these kinds of services free of `EventBus` and handler references. The handler can inject a callback object that implements a callback protocol the service can invoke. The handler's implementation of this protocol holds a weak `EventBus` reference internally, and publishes API functions that send events back into the bus when the service calls them. If the bus has deallocated, the callback object becomes a no-op and the service does not retain the bus or point back to its handler.

See ``EventBusTests/EventBusDeepExampleTests/EventBusDeepExampleTestsCallback/weakEventBusServiceCallbackExample()``
