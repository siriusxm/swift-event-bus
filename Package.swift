// swift-tools-version: 6.2
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

import PackageDescription

let package = Package(
    name: "EventBus",
    platforms: [
        .iOS(.v16),
        .tvOS(.v16),
        .macOS(.v13),
        .watchOS(.v10),
    ],
    products: [
        .library(
            name: "EventBus",
            targets: ["EventBus"]
        ),
        .library(
            name: "EventBusTestSupport",
            targets: ["EventBusTestSupport"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.3.2"),
    ],
    targets: [
        .target(
            name: "EventBus",
            dependencies: [
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
            ],
            exclude: ["Documentation.docc"]
        ),
        .target(
            name: "EventBusTestSupport",
            dependencies: [
                "EventBus",
            ]
        ),
        .testTarget(
            name: "EventBusTests",
            dependencies: [
                "EventBus",
                "EventBusTestSupport",
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras"),
            ]
        ),
    ]
)
