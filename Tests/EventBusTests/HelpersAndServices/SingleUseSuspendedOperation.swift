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

actor SingleUseSuspendedOperation {
    private var hasFinished = false
    private var hasStarted = false
    private var finishContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var startContinuation: CheckedContinuation<Void, Never>?

    func suspendUntilReleased() async {
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
            hasStarted = true
            startContinuation?.resume()
            startContinuation = nil
        }
        hasFinished = true
        finishContinuation?.resume()
        finishContinuation = nil
    }

    func waitUntilSuspended() async {
        guard !hasStarted else {
            return
        }

        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func waitUntilFinished() async {
        guard !hasFinished else {
            return
        }

        await withCheckedContinuation { continuation in
            finishContinuation = continuation
        }
    }
}
