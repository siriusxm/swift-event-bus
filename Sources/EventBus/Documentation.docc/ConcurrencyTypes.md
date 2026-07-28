# Concurrency Types in EventBus

## Overview

The `EventBus` sits at the center of your system's asynchronous code, invoking handlers as events arrive. This positioning lets it factor out features that handlers would otherwise implement redundantly. Of these features, `concurrencyType` is one of the most powerful. It lets you declare what happens when events arrive faster than a handler can process them: run in parallel, queue them, or cancel and restart — no per-handler concurrency code needed.

The `EventBus` concurrency types are patterned after the standard "merge" flattening operators in RX frameworks. Where in RX you would invoke a flattening operator for a stream of observables coming into a handler, using the `EventBus` you declare a `concurrencyType` in the handler's type declaration:

| concurrencyType | RX merge function | Behavior |
|-------------------|-------------------|----------|
| .parallel | mergeMap (a.k.a. flatMap) | Every event spawns its own handler invocation; all run concurrently. (Default.) |
| .serial | concatMap | Events queue in arrival order; each invocation runs to completion before the next starts. |
| .restart | switchMap | A new event cancels the in-flight invocation, if any, and starts a fresh one. |

A fourth behavior, corresponding to RX's `exhaustMap`, is not currently included in `EventBus`. In that model, a new event is dropped before execution if a previous invocation is still in flight.

The default `concurrencyType` for `BusEvent` handler declarations is `.parallel`, so you only need to declare a `concurrencyType` when you want concurrency other than `.parallel`. Declare it with a single line in the handler type:

```swift
@RequestResponseHandlerTypes
enum MyHandler: RequestResponsePayloadHandler {
    typealias RequestPayload = MyData
    static let concurrencyType: EventBus.ConcurrencyType = .serial
}
```

To choose a `concurrencyType`, consider what should happen when events arrive faster than the handler can process them, taking into account the requirements of the service function that the handler invokes. The sections below describe each type, the kinds of services that benefit from it, and where to find detailed examples.

## Parallel — mergeMap

Use `.parallel` when each invocation of the handler is independent of every other. New events spawn new handler tasks and the `EventBus` processes them concurrently. So if ten events arrive in quick succession, ten handler tasks will run in parallel and each one will publish its response independently when it completes.

This is the right fit for stateless, idempotent, or read-mostly services where invocations don't share mutable state. Common examples:
- Analytics and logging handlers that fan-out to remote sinks.
- Image or content fetching handlers where each request is keyed to a different resource.
- Pure transformation services that compute a response with no side effects.

If a handler's service holds mutable state and you need consistent read/write access to that state in a single handler function, `.parallel` is usually the wrong choice — invocations can race and stomp on each other. Either move the state-management responsibility into a serialized atomic function in the service (using an `actor`, a `LockIsolated` value, or similar), or pick `.serial` instead.

`.parallel` is the default, so this declaration is equivalent to omitting `concurrencyType` entirely:

```swift
struct AnalyticsService: Sendable {
    @RequestResponseHandlerTypes
    enum LogPageView: RequestResponsePayloadHandler {
        typealias RequestPayload = String  // a screen name
        static let concurrencyType: EventBus.ConcurrencyType = .parallel
    }

    let handlers: [any Handlable] = [
        LogPageView.handlerRegistration { screenName in
            // Each event runs concurrently; analytics writes do not block each other.
            await Telemetry.shared.record(.pageView(screenName))
        },
    ]
}
```

`.parallel` is the default `concurrencyType` for `RequestResponsePayloadHandler` and `RequestResponseTrackedBusEventHandler`, so every example in the README is also a `.parallel` example. See ``EventBusTests/EventBusExampleTests/EventBusReadMeExampleTests/readMeExample1()`` for the most basic of these.

## Serial — concatMap

Use `.serial` when each invocation of the handler depends on the cumulative effect of previous invocations, or operates on a shared resource that cannot tolerate concurrent access. Events queue in the order they arrive and the `EventBus` runs them one at a time, completing each invocation before starting the next.

This is the right fit for handlers whose services mutate ordered state or interact with single-writer external systems. Common examples:
- Queue mutations (enqueue, dequeue, reorder), where running two mutations concurrently would corrupt the queue.
- Persistence handlers that write a single file or row, where two concurrent writes would either lose data or require explicit locking.
- Multi-step transactions on shared in-memory data structures, where each event represents one step and steps must complete in order.

If a handler's service is fundamentally stateless or its work is independent across invocations, `.serial` is unnecessary overhead — events can pile up under load even though the `EventBus` could otherwise have run them concurrently. Pick `.parallel` for those cases.

```swift
struct PlaybackQueueService: Sendable {
    @RequestResponseHandlerTypes
    enum EnqueueTrack: RequestResponsePayloadHandler {
        typealias RequestPayload = TrackID
        static let concurrencyType: EventBus.ConcurrencyType = .serial
    }

    let queue: PlaybackQueue
    var handlers: [any Handlable] {
        [EnqueueTrack.handlerRegistration { [queue] trackID in
            // Serial concurrency guarantees enqueues land in the order they were sent,
            // and that no two enqueue operations ever race on `queue`'s internal state.
            await queue.append(trackID)
        }]
    }
}
```

There are two ways to provide serial access to a service's mutable state: have the service serialize itself (typically by being an `actor`) and use a `.parallel` handler, or leave the service unguarded and use a `.serial` handler so that the `EventBus` does the serialization at the handler boundary. See ``EventBusTests/EventBusDeepExampleTests/EventBusDeepExampleTestsConcurrencyTypes/serialAccessViaActorService()`` and ``EventBusTests/EventBusDeepExampleTests/EventBusDeepExampleTestsConcurrencyTypes/serialAccessViaSerialHandler()`` for both patterns side by side. For a `.serial` tracked handler that coordinates a nested `.parallel` payload handler, see ``EventBusTests/EventBusDeepExampleTests/EventBusDeepExampleTestsConcurrencyTypes/serialTrackedBusEventHandler()``.

## Restart — switchMap

Use `.restart` when only the latest event matters and any in-flight processing of older events represents wasted work that can be safely abandoned. When a new event arrives, the `EventBus` cancels the previously running invocation (if any) before starting the new one.

This is the right fit for "latest intent" UI patterns where the user supersedes their own earlier intent before processing finishes. Common examples:
- Search-as-you-type, where the response to "ap" is irrelevant once the user has typed "apple".
- Scrub bars and other continuous-input UI controls, where intermediate seek positions are obsolete by the time they would land.
- Route or navigation handlers that recompute when destination inputs change, where the in-flight computation against stale inputs no longer matters.

Note that `.restart` is *cooperative*. When the previous invocation is cancelled, its `Task` is marked cancelled but it does not stop running until it reaches a suspension point (an `await`) and Swift Concurrency checks the cancel flag. So you are responsible for designing your handler bodies to either reach a suspension point promptly (the common case — most async handlers `await` something), or to provide a synchronous fast path when the work is trivial enough that running it to completion is cheaper than honoring cancellation.

```swift
struct SearchService: Sendable {
    @RequestResponseHandlerTypes
    enum Search: RequestResponsePayloadHandler {
        typealias RequestPayload = String
        typealias ResponsePayload = [SearchResult]
        static let concurrencyType: EventBus.ConcurrencyType = .restart
    }

    let backend: SearchBackend
    var handlers: [any Handlable] {
        [Search.handlerRegistration { [backend] query in
            // If a newer query arrives while this fetch is in flight, the `EventBus`
            // cancels this invocation and starts handling the newer query instead.
            try await backend.fetchResults(for: query)
        }]
    }
}
```

See ``EventBusTests/EventBusDeepExampleTests/EventBusDeepExampleTestsConcurrencyTypes/restartHandlerCancelsCleanly()`` for a search-as-you-type handler that cancels cleanly when a new event arrives.
