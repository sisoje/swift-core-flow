#!/bin/sh
# CI entry point for the hosted UI-test suite, no coverage. Each test
# launches its own scenario (launchApp passes a TestPayload per launch).
# Xcode runs the same scheme with its own settings.
set -eu
cd "$(dirname "$0")"

xcodegen generate

xcodebuild build-for-testing \
    -project CoreFlowHosted.xcodeproj \
    -scheme CoreFlowHostApp \
    -destination "generic/platform=iOS Simulator" \
    -enableCodeCoverage NO

# Boot explicitly, after the build: on a cold runner the first launch through
# xcodebuild timed out ("Timed out while launching application via Xcode",
# 129 s), and a boot started in the background does not overlap anything —
# xcodebuild blocks on CoreSimulator until the boot finishes (~200 s
# measured, twice, whatever destination it was given).
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
xcrun simctl bootstatus "iPhone 17 Pro" -b

xcodebuild test-without-building \
    -project CoreFlowHosted.xcodeproj \
    -scheme CoreFlowHostApp \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
    -collect-test-diagnostics never \
    -enableCodeCoverage NO

# Quiescent for the warm-simulator cache saved at the end of the CI job.
xcrun simctl shutdown "iPhone 17 Pro"
