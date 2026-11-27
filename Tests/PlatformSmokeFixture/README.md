# Platform smoke builds

This separate Swift 6.2 package checks that consumers can compile and link Rundown tests for its supported Apple platforms. It depends on the local Rundown package and uses ordinary imports, with separate targets for XCTest and Swift Testing.

The examples cover synchronous and asynchronous specs, main-actor isolation, around hooks, and per-example fixtures. The fixture excludes the main suite's macOS-only subprocess tests and the experimental Swift 6.4 `@Spec` discovery API.

## Build destinations

The deployment targets come from this fixture's `Package.swift` and match Rundown's minimum versions.

| Platform | Xcode destination | Minimum deployment target |
| --- | --- | --- |
| iOS Simulator | `generic/platform=iOS Simulator` | iOS 17 |
| tvOS Simulator | `generic/platform=tvOS Simulator` | tvOS 17 |
| watchOS Simulator | `generic/platform=watchOS Simulator` | watchOS 10 |
| Mac Catalyst | `generic/platform=macOS,variant=Mac Catalyst` | Mac Catalyst 17 |

From this directory, build both consumer test targets with:

```sh
xcodebuild \
  -scheme PlatformSmokeFixture-Package \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/RundownPlatformSmoke \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing
```

Substitute a destination from the table to check another platform. These builds use the installed SDK and do not boot simulators or execute tests. They check build compatibility at the minimum deployment targets; they do not establish runtime behavior on those operating system versions.

CI builds all four destinations using Xcode 26.0.1. The macOS test jobs execute both the main suite and these consumer examples across Swift 6.2, 6.3, and 6.4. To execute the consumer examples on macOS from the repository root:

```sh
swift test --package-path Tests/PlatformSmokeFixture
```
