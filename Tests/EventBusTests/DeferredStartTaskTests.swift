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

import ConcurrencyExtras
@testable import EventBus
import Testing

@Suite("DeferredStartTask tests")
struct DeferredStartTaskTests {
    @Test
    func startRunsOperation() async {
        let operationRan = LockIsolated(false)
        let deferredTask = DeferredStartTask {
            operationRan.setValue(true)
        }

        deferredTask.start()
        await deferredTask.waitForCompletion()

        #expect(operationRan.value)
    }

    @Test
    func discardSkipsOperation() async {
        let operationRan = LockIsolated(false)
        let deferredTask = DeferredStartTask {
            operationRan.setValue(true)
        }

        deferredTask.discard()
        await deferredTask.waitForCompletion()

        #expect(!operationRan.value)
    }

    @Test
    func cancellationBeforeStartStillRunsOperation() async {
        let operationObservedCancellation = LockIsolated(false)
        let deferredTask = DeferredStartTask {
            operationObservedCancellation.setValue(Task.isCancelled)
        }

        deferredTask.task.cancel()
        deferredTask.start()
        await deferredTask.waitForCompletion()

        #expect(operationObservedCancellation.value)
    }
}
