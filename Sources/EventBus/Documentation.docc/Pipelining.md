# Pipelining

## Overview

Pipelining organizes a multi-step process into a chain of small functions, each consuming the previous step's output. This keeps the top-level process readable while integration details and logic move into subroutines. It fits naturally with `BusEvent` protocols: events already carry the process state in their payloads and the bus integration to send and chain successors, so they naturally become the data passing through the pipeline.

A controller that uses pipelining can read like the process it is modeling. This example shows the top level of a pipeline process:

```swift
return try await inputEvent
    .selectColor()?
    .selectFood()?
    .writeCritique()
```

See ``EventBusTests/EventBusDeepExampleTests/EventBusDeepExampleTestsPipelining/pipelinedControllerFlow()`` for a complete working example.

## Pipeline Functions Live On Events

Without pipelining, a multi-step handler tends to accumulate local variables that exist only to unwrap the previous result and feed the next function. For example:

```swift
guard let colorEvent = try await ColorSelectionEvent.SelectColor.sendAndWaitForResponse(
    inputEvent: inputEvent
) else {
    return nil
}

guard let foodEvent = try await FoodSelectionEvent.SelectFood.sendAndWaitForResponse(
    inputEvent: colorEvent,
    payload: colorEvent.busEvent.payload
)
else {
    return nil
}

return try await foodEvent.writeCritique()
```

The same flow is more efficiently expressed as a pipeline. In an `EventBus` pipeline, event payloads define the evolving process data state, and the pipeline subroutines are defined as `TrackedBusEvent` object member functions. Each pipeline function is defined in an extension on the event type whose payload it uses as input. The input event is available as `self`, and its typed payload is available through `busEvent.payload`.

This makes the top-level process simple and easy to read:

```swift
return try await inputEvent.selectColor()?
    .selectFood()?
    .writeCritique()
```

The key factor is that each pipeline function has direct access to the event and payload it is extending. For example, `selectFood()` is defined on the color selection response, so it can use `self` as the chained input event and `busEvent.payload` as the color:

```swift
private extension ColorSelectionEvent.SelectColor.TrackedResponse {
    func selectFood() async throws -> FoodSelectionEvent.SelectFood.TrackedResponse? {
        try await FoodSelectionEvent.SelectFood.sendAndWaitForResponse(
            inputEvent: self,
            payload: busEvent.payload
        )
    }
}
```

This removes repeated local declarations while keeping the data accessible where it is needed. The top-level handler shows the order of the work, while the subroutines declared in event extensions own the data integration needed for each step.

## Factoring A Process Into A Pipeline

To create a pipeline process, you need to factor your process into discrete steps that will become the top-level subroutines. The common shape of a pipeline process is that the top level just shows the process steps calling each other in sequence, so any logic gets pushed down into the subroutines that implement these process steps. If your process is already defined as a series of `BusEvent`s then the top-level factoring is already done.

The most common pipeline function takes the current event as the `inputEvent` for the next request-response event, then maps the current payload into the next request payload and returns the result of the `EventBus` `sendAndWaitForResponse`.

In the pipelining example, the color selection response payload is a `String`. `selectFood()` passes that string as the request payload to the food selection event:

```swift
private extension ColorSelectionEvent.SelectColor.TrackedResponse {
    func selectFood() async throws -> FoodSelectionEvent.SelectFood.TrackedResponse? {
        try await FoodSelectionEvent.SelectFood.sendAndWaitForResponse(
            inputEvent: self,
            payload: busEvent.payload
        )
    }
}
```

Sometimes the current event has more data than the next service requires as input. In that case, the pipeline function should narrow the current payload into the next event's request payload:

```swift
extension MealControllerEvent.MakeLunch.TrackedRequest {
    func selectMainIngredient() async throws -> IngredientSelectionEvent.SelectMainIngredient.TrackedResponse? {
        try await IngredientSelectionEvent.SelectMainIngredient.sendAndWaitForResponse(
            inputEvent: self,
            payload: IngredientSelectionPayload(
                dinerName: busEvent.payload.dinerName,
                dietaryRestrictions: busEvent.payload.dietaryRestrictions
            )
        )
    }
}
```

In most pipeline handlers, the event type that receives the pipeline method matches the type that already has most of the data the method needs. If a later method still needs data from the original input event, or any other data that is available at the top level of the process, pass the data explicitly to the pipeline functions:

```swift
.reserveTable(guestCount: inputEvent.busEvent.payload.numberOfGuests)
.writeReceipt(timeOfMeal: mealStartTime)
```

Do this narrowly as needed. A pipeline should make the main data flow visible, not force every step to carry every value that has ever existed in the process.

## Returning The Overall Result

There are two common ways to return from a pipelined controller.

First, the final pipeline function in the chain can return the public response event directly. In the pipelining example, `writeCritique()` appends the controller's `MakeColoredFood.response` and returns that tracked response:

```swift
return await appendEvent(
    PipeliningColoredFoodControllerEvent.MakeColoredFood.response(payload: .success(
        PipeliningColoredFoodSuccess(
            colorAndFood: busEvent.payload,
            critique: critique
        )
    ))
)
```

Then the top-level controller can return the final pipeline result:

```swift
return try await inputEvent.selectColor()?
    .selectFood()?
    .writeCritique()
```

Second, the pipeline can produce a detailed internal process event, and the top-level controller can append a simpler public response at the end. This is useful when the process caller does not care about the detail payload from the final internal event, but does want a clear overall status.

For example, a controller might make colored food, eat it, and return only whether the meal process succeeded. The caller does not need the detailed colored-food payload or the private result of the eating service:

```swift
struct MealProcessResult {
    enum Status {
        case success
        case failed
    }

    let status: Status
}

return try await inputEvent
    .makeColoredFood()?
    .eatMeal()?
    .appendEvent(
        MealControllerEvent.EatColoredFood.response(payload: MealProcessResult(status: .success))
    )
```

Using this method, the internal event chain can be detail-rich for logging, testing, and troubleshooting, while the public controller response stays intentionally small.

## Local Service Calls In Pipeline Processes

Processes may mix direct calls to subroutines or local service functions with `BusEvent` `sendAndWait` calls. In that case you need to define the subroutines for the direct call process steps the same way you do for `BusEvent` steps. These functions will return the `self` of the `TrackedBusEvent` type they are a member of.

Or if the subroutines return new results you can make a wrapper `TrackedBusEvent` type to accumulate the needed data from the previous event payload and the new data created by the local processing into a new type of result. You can then append this result to the previous step and pass it to the next step in the pipeline.

For example, a process might select a color via a bus event, then validate that color against a local inventory service before going on to the food step. The validation is a pipeline function on the color response, but its body calls the local service directly rather than through another `BusEvent`. Because the step does not produce new payload data, the function returns `self` so the pipeline continues with the same event:

```swift
private extension ColorSelectionEvent.SelectColor.TrackedResponse {
    func validateColor(_ validator: ColorValidator) async throws -> Self {
        try await validator.assertAvailable(busEvent.payload)
        return self
    }
}
```

If the validation step produces process data, then the step would look like this:

```swift
struct ValidatedColor {
    let color: String
    let validationRecord: ValidationRecord
}

enum ColorValidationEvent: SimpleBusEventType {
    typealias Payload = ValidatedColor
}

extension ColorSelectionEvent.SelectColor.TrackedResponse {
    func validateColor(_ validator: ColorValidator) async throws -> ColorValidationEvent? {
        return await appendEvent(ColorValidationEvent(payload:
            ValidatedColor(
                color: busEvent.payload,
                validationRecord: try await validator.assertAvailable(busEvent.payload)
            )
        ))
    }
}
```

At the top level, the direct-call step chains alongside the bus-driven steps with the same shape:

```swift
return try await inputEvent.selectColor()?
    .validateColor(validator)?
    .selectFood()?
    .writeCritique()
```

## Main Events And Side Effects

Whether a step is part of the main process or a side effect changes how you code it in `EventBus` — two questions guide your implementation:

- Is the result of the step used in process logic or as input to later process steps?
- Can the process complete and settle all affected state needed to test if it succeeded before this step is complete?

If the answer is no to both of these questions, the step is a classic side effect, and can be executed in parallel with the rest of the process. Code the pipeline function that executes this step as follows:

```swift
func sendNotification() async -> Self {
    await NotificationEvent.send(
        inputEvent: self,
        payload: busEvent.payload
    )
    return self
}
```

The implication of this method for side effects is that the results of the event handler are excluded from the process event stream for purposes of testing and troubleshooting. But this doesn't mean you can't test the side effect results, just that you need a separate test that kicks off the process, but waits for the side effect event result rather than the process result. The `EventBus` includes a type `SimpleBusEventLink` that allows you to easily run such tests, like this:

```swift
enum TestLink: SimpleBusEventLink {
    typealias TriggerEvent = PipeliningColoredFoodControllerEvent.MakeColoredFood.RequestEvent
    typealias ResponseEvent = NotificationEvent.ResponseEvent
}
let response = try await TestLink.sendAndWaitForResponse(eventBus: eventBus)
```

See ``EventBusTests/EventBusDeepExampleTests/EventBusDeepExampleTestsPipelining/pipelineControllerServiceTestInterimResponse()`` for a working example of using a `SimpleBusEventLink` to wait on the color response event rather than the process completion response.

If the answer to the first question above is that the results of the process step are not used for later steps, but the answer to the second question is still no, that the process is not complete until the process step is done, then you can have the process wait for the step, but still exclude its results from the event chain. This will come up if a process step changes the application state or an external system state but does not change the internal process state. In this case, you will want the process to await the step's completion so that external change does not race with the completion of the whole process. To put that wait inline with the rest of the process, code like this:

```swift
func sendNotification() async throws -> Self {
    _ = try await NotificationEvent.sendAndWaitForResponse(
        inputEvent: self,
        payload: busEvent.payload
    )
    return self
}
```

Even if application execution is not affected by the process timing, this method ensures process tests run consistently if they check application state after the process completion event returns.

## Optional Event sendAndWaitForResponse Returns

All `sendAndWait` and `appendEvent` functions return optionals, and a `nil` return means the `EventBus` has been deallocated mid-call. When that happens, your handler must exit immediately. Pencils down. No logging, reporting, state management, or attempted recovery allowed — any of these can crash the system during teardown.

Pipeline handler functions allow a compact method for draining out of the bottom of the function when a `nil` is returned anywhere along the event chain, which has become a best practice in handler writing. This is why the pipeline examples always use optional chaining like this:

```swift
return try await inputEvent.selectColor()?
    .selectFood()?
    .writeCritique()
```

## Optionals In Pipeline Payloads

In contrast to optional events, optional payload data has nothing to do with `EventBus` conventions and everything to do with the process you are implementing. Complex asynchronous processes that use the `EventBus` often have variations of valid service results or recoverable runtime failures that can be expressed as optional data.

The consequence of optional data in Swift is that it spawns unwrapping logic in the form of `if let` or `guard let` statements where the negative case has to be handled every time the data is referenced. Repeatedly unwrapping the same optional is an anti-pattern in Swift, so it is common for `BusEvent` payloads to evolve through a process where non-optional references to data can be stored once it is unwrapped.

In the pipelining example, a second food is optional because the system can validly make a critique with either one food or two. This implementation minimizes the logic needed to handle this variation to a single guard statement:

```swift
private func requestCritiqueResponse() async throws -> String? {
    guard let food2 = busEvent.payload.food2 else {
        return try await CritiqueWritingEvent.WriteSingleFoodCritique.sendAndWaitForResponse(
            inputEvent: self,
            payload: busEvent.payload
        )?.busEvent.payload
    }

    return try await CritiqueWritingEvent.WriteDoubleFoodCritique.sendAndWaitForResponse(
        inputEvent: self,
        payload: PipeliningColorAndTwoFoods(
            color: busEvent.payload.color,
            food1: busEvent.payload.food1,
            food2: food2
        )
    )?.busEvent.payload
}
```

It is another anti-pattern to use optional payload fields just because a value is not available at the beginning of the process. If a value is created or validated in a later process step, prefer creating a new event payload where the value is non-optional. The double-food critique branch does this by converting the optional `food2` field into a `PipeliningColorAndTwoFoods` payload where the second food is guaranteed to exist:

```swift
return try await CritiqueWritingEvent.WriteDoubleFoodCritique.sendAndWaitForResponse(
    inputEvent: self,
    payload: PipeliningColorAndTwoFoods(
        color: busEvent.payload.color,
        food1: busEvent.payload.food1,
        food2: food2
    )
)?.busEvent.payload
```

After this step, the double-food critique handler receives a payload with a non-optional `food2`, so it does not need to repeat the same validation.

For an example of the branch taken when `food2` is `nil`, see ``EventBusTests/EventBusDeepExampleTests/EventBusDeepExampleTestsPipelining/pipelinedControllerFlowWithoutSecondFood()``.

## Calling Multiple Services In One Pipeline Function

A pipeline function should usually model one process step, but one step may need more than one service call. If those calls are independent, run them together and consolidate the results into one response payload.

The pipelining example's food selection handler asks two food services for independent answers, runs their tasks in parallel, then returns a single `PipeliningColorAndFood` result:

```swift
FoodSelectionEvent.SelectFood.handlerRegistration { color in
    async let food1 = primaryFoodService.selectPrimaryFood()
    async let food2 = secondaryFoodService.selectSecondaryFood()
    return try await PipeliningColorAndFood(color: color, food1: food1, food2: food2)
}
```

This keeps the pipeline simple. The next step receives one typed payload rather than needing to know which services produced which pieces of data. It also gives tests and loggers one result event to inspect.

Use this pattern when:

- The service calls are part of the same conceptual process step
- The calls can run independently
- The next pipeline step should depend on the combined result, not the intermediate service details

If the service calls need different timeout, retry, or concurrency rules, consider modeling them as separate events instead. The pipeline should not hide meaningful process boundaries.

## Structured Exception Handling

Pipeline functions should throw when the process cannot continue normally. The top-level controller should use a `do`/`catch` block to translate process failures into the public response shape.

In the pipelining example, service failures throw `PipeliningExampleError`. The top-level controller catches that error and returns with a failure response appended to the input event:

```swift
PipeliningColoredFoodControllerEvent.MakeColoredFood.handlerRegistration { inputEvent in
    do {
        return try await inputEvent.selectColor()?
            .selectFood()?
            .writeCritique()
    } catch let error as PipeliningExampleError {
        return await inputEvent.appendEvent(
            PipeliningColoredFoodControllerEvent.MakeColoredFood.response(payload: .failure(error))
        )
    }
}
```

Individual pipeline functions should throw when they cannot produce a valid next state. The top-level handler can catch all process errors and append a failure response with the data the caller expects.

For failure-path examples at each pipeline stage, see ``EventBusTests/EventBusDeepExampleTests/EventBusDeepExampleTestsPipelining/pipelinedControllerFlowWhenColorServiceFails()``, ``EventBusTests/EventBusDeepExampleTests/EventBusDeepExampleTestsPipelining/pipelinedControllerFlowWhenFoodServiceFails()``, and ``EventBusTests/EventBusDeepExampleTests/EventBusDeepExampleTestsPipelining/pipelinedControllerFlowWhenCritiqueServiceFails()``.

This style has two advantages:

- Pipeline functions can assume their input event's payload is valid by context, and so avoid repeatedly re-validating the same data.
- Public error mapping is centralized at the controller boundary instead of repeated in every process step.

Prefer throwing from a pipeline function when the rest of the pipeline is invalid. 
Prefer returning `self` when a step is optional and the process can continue unchanged. 
Prefer appending an explicit failure response when the function is at a public boundary and the caller needs a structured result.

## Pipeline Function Size

Pipeline functions should be small enough that the top-level process remains trustworthy. A good default is:

- One pipeline function sends one event, transforms one payload, or applies one state transition.
- A pipeline function may call multiple services when it consolidates one conceptual result.
- Branches inside a pipeline function should produce the same type of result.
- If a function is hard to describe as a single process step, split it into smaller pipeline functions. A classic sign this is occurring is if you need to use conjunctions like "And" or "Or" in the function's title.

The goal is not to make the top-level handler artificially short. The goal is to put each line of the top-level handler at the level of the process story and put the mechanical payload mapping in the subroutines with the events that need the data.

## Cancellation In Pipeline Functions

It is a best practice to check for cancellation before each suspension point/`await` in an asynchronous process, and in `EventBus` processes to check before any call that could change state. For pipeline functions this means the cancellation checks are going to be down in the pipeline subroutines rather than at the top-level function.

```swift
private extension PipeliningColoredFoodControllerEvent.MakeColoredFood.TrackedRequest {
    func selectColor() async throws -> ColorSelectionEvent.SelectColor.TrackedResponse? {
        try Task.checkCancellation()
        return try await ColorSelectionEvent.SelectColor.sendAndWaitForResponse(inputEvent: self)
    }
}
```

In most cases cancellation does not have to be caught at the top level of a process. If state changes are atomic, then cancellation before the state change can drain out of the top-level handler, and cancellation after the state change means the process has already completed from the application's point of view, so it's too late to cancel. However, if your process includes incremental state updates, partial recovery, or degraded states, catching `CancellationError` and attempting cleanup may need to be part of your solution.

## Enabling BusEvent Extensions

You may have encountered a compiler error when you tried to extend a `BusEvent` or `TrackedBusEvent` type to make a pipeline function.
The compiler error would be something like:
`Extension of type 'YourTypeName.TrackedRequest' (aka 'TrackedBusEvent<ObjectIdentifier, YourPayloadType>') must be declared as an extension of 'TrackedBusEvent<ObjectIdentifier, YourPayloadType>'`

The problem is a Swift language limitation. When you declare events that conform to the `SimpleBusEventType` or any of the Handler types, the protocol extensions internally declare the event types as needed for triggering events, requests, and responses. But Swift doesn't reference those as valid when you declare your conforming event.

There are several ways to fix this. Easiest is to use macros that the `EventBus` project provides that declare all the right definitions for you. If you look at the ``EventBusTests/EventBusDeepExampleTests/EventBusDeepExampleTestsPipelining`` file where the shared event declarations are at the top, you'll see examples like this:

```swift
    @RequestResponseHandlerTypes
    enum SelectColor: RequestResponsePayloadHandler {
        typealias ResponsePayload = String
    }
```

Use the corresponding type macro for every event and handler declaration to generate the event aliases needed by extensions. The macro must match the protocol adopted by the declaration:

    @SimpleBusEventTypes
    @ResponseHandlerTypes
    @RequestResponseHandlerTypes
    @LinkedEventHandlerTypes

Alternatively, if you don't want to use macros, you can declare the event types within your event declaration manually, like this:

```swift
    enum SelectColor: RequestResponsePayloadHandler {
        typealias ResponsePayload = String
        typealias TrackedResponse = TrackedBusEvent<ObjectIdentifier, ResponsePayload>
    }
```

Or you can use the internal base type for the extension:

```swift
private extension TrackedBusEvent<ObjectIdentifier, ()> {
    func selectColor() async throws -> ColorSelectionEvent.SelectColor.TrackedResponse? {
        try Task.checkCancellation()
        return try await ColorSelectionEvent.SelectColor.sendAndWaitForResponse(inputEvent: self)
    }
}
```

We'd recommend using the macros to simplify your code and keep internal type details from leaking out of the event definitions, but any of these solutions will work.

There are extensions to these macros that help reduce integration boilerplate for events that have complex payloads. These macros internally call the payload initializers and put the initializer's fields directly into the `EventBus` integration methods for declaring and sending events. For these macros, mark the payload initializer with `@BusEventPayloadInit`, then use the matching payload-and-types macro:

    @SimpleBusEventPayloadAndTypes("field")
    @ResponseHandlerPayloadAndTypes(triggerEvent: ["field"], response: ["field"])
    @RequestResponseHandlerPayloadAndTypes(request: ["field"], response: ["field"])
    @LinkedEventHandlerPayloadAndTypes(triggerEvent: ["field"], response: ["field"])

See <doc:EventGuide#Integrating-Complex-Payloads> for requirements and a complete example.
