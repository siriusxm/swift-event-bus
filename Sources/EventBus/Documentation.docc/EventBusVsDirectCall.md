# `EventBus` vs Direct Call Systems

## Overview

Adopting the `EventBus` is a big cost-benefit decision. It reshapes how processes are expressed and how components communicate. And it factors out patterns that recur across complex asynchronous systems. So it is likely overkill for a simple synchronous system, but pays off as an asynchronous system scales. For general software engineering discussion of events see [here](https://martinfowler.com/eaaDev/EventNarrative.html).

## `EventBus` Features

### Event Definition and Handling Framework

The `EventBus` provides protocols with reusable utilities for defining events and connecting them to handling functions with minimal boilerplate and maximal static validity checking. If your system is already defined with asynchronous events such as user actions, media completions, or timer-driven updates, then an event-driven middleware may be a natural fit. Otherwise plan on more refactoring costs. For greenfield projects you have the advantage of deciding on architecture first. See <doc:FactoringComplexSystems> for more detail.

### Decoupled Service Calls

As a system grows and you factor it into separate services, the dependency graph between them multiplies quickly. The `EventBus` lets services invoke each other without direct code dependencies, sharing only `BusEvent` data definitions.

This collapses the code-dependency graph and lets you:

- Build, test, and version services independently
- Manage system creation, initialization, and teardown more easily

### Single Shared Publishing Channel

Though `Combine` and `AsyncSequence` are powerful tools, they can make multi-step asynchronous processes difficult to maintain when used by themselves. They require you to code each process step as a separate closure, and it is difficult to organize those closures in a way that can be traced as a coherent process. Worse, if a publisher is split and recombined, it can create echoes — similar updates racing each other downstream, where the last to arrive determines what subscribers see.

The `EventBus` simplifies this by providing:

- A single asynchronous channel for all processes to share
- A single implementation method with `BusEvent`s and handler functions that provides a framework to organize code
- A unique monotonically increasing index for each runtime processing step in an event's lifecycle, so events can be compared to see their order of execution
- Event history storage within each process instance, which can be logged or examined at breakpoints

### Asynchronous Function Execution Framework

Because the `EventBus` executes asynchronous inter-service calls, it is in a central place to provide some valuable features:

- **Standard Timeouts** — Any async call can hang in production, and it happens more often than we'd hope. At scale, that means some fraction of your users will hit stuck threads that go unnoticed. The `EventBus` lets you set default timeouts so these threads don't accumulate silently, and you're informed when any process stalls.

- **Error Propagation** — Errors are propagated through the `EventBus` from handler functions back through `sendAndWait` functions and thrown to the requesting function. This allows you to model complex processes with structured exception handling where data can be known to be valid by context, and all process failures from any participating service can be handled in standard `catch` blocks at the top level of the process.

- **Built-in Concurrency Patterns** — The `EventBus` registers handler functions with built-in concurrency patterns, including parallel, serial, and self-cancelling concurrency. You can invoke these patterns simply by declaring a `concurrencyType` in your event handler declaration. See <doc:ConcurrencyTypes> for details on each pattern, when to use it, and example handlers.

## When to Use the `EventBus`

Use this table as a guide.

| Direct Calls May Be Better | `EventBus` May Be Better |
|---------------------------|------------------------|
| More synchronous operations | More asynchronous operations |
| Single-step or few-step processes | Multi-step processes |
| Fewer components | More components |
| Smaller component APIs | Larger component APIs |
| Less component interaction | More component interaction |
| No race condition potential | Possible race conditions |
| Single-thread operations | Parallel and serial concurrency |

## Example: Real-World Scale

An example production scale system that uses the `EventBus` has:

- **~10 components**, 7 of which communicate asynchronously through the `EventBus`
- **~20 multi-step asynchronous processes**, the most complex having around a dozen top-level steps (decomposing to ~50 detailed steps)
- **~115 internal events** total, with components handling up to 25 events each

Though there is no hard-and-fast rule, this system is well over the line of complexity where the `EventBus` has helped to create a better-organized, more maintainable system than the legacy version it replaced.
