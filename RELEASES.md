# EventBus releases

## Current release: 1.0.0-beta.1

`1.0.0-beta.1` is the first public prerelease of `EventBus` and establishes the `EventBus` 1.0 public API. SiriusXM intends to preserve source compatibility from this beta through the stable `1.0.0` release. During the public beta, development will focus on community validation, documentation, reliability, and backward-compatible improvements so adopters can move forward without disruption.

The stable release will follow a period of public availability and evaluation.

- [Release notes for 1.0.0-beta.1](Documentation/Releases/1.0.0-beta.1.md)
- [GitHub releases](https://github.com/siriusxm/swift-event-bus/releases)

## Swift Package Manager channels

`EventBus` is distributed as a source package. Swift Package Manager resolves the repository and Git tag directly.

### Supported prerelease

Use an exact requirement while the supported release is a prerelease:

```swift
dependencies: [
    .package(
        url: "https://github.com/siriusxm/swift-event-bus.git",
        exact: "1.0.0-beta.1"
    )
]
```

Current supported prerelease: [1.0.0-beta.1](https://github.com/siriusxm/swift-event-bus/releases/tag/1.0.0-beta.1)

### Stable release

No stable release is available yet. After `1.0.0` is published, this section will contain the recommended `from:` requirement and a link to the corresponding GitHub release.

### Tip of tree

To test the latest development state:

```swift
dependencies: [
    .package(
        url: "https://github.com/siriusxm/swift-event-bus.git",
        branch: "main"
    )
]
```

The `main` branch is unstable and unsupported. It may change without notice and should not be used for production dependencies.

## Supported versions

| Version | Channel | Support status | Release notes |
| --- | --- | --- | --- |
| 1.0.0-beta.1 | Prerelease | Supported preview | [Notes](Documentation/Releases/1.0.0-beta.1.md) |

### Previous supported versions

There are no previous releases. As support moves forward, this section will retain installable back-revisions, links, and their support status.

## Versioning and support

`EventBus` uses [Semantic Versioning](https://semver.org/). A version is available to Swift Package Manager when its Git tag is published. GitHub Releases provide release notes and source archives for those same tags.

Prerelease support applies only to the currently listed supported prerelease. Stable-version support and compatibility commitments will begin with `1.0.0` and will be documented here.
