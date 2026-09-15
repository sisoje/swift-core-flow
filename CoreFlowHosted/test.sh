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

# Boot explicitly, never through the first app launch: on a cold runner that
# timed out ("Timed out while launching application via Xcode", 129 s). CI
# may already have the boot in flight (started before the build; `|| true`
# covers "already booting"), bootstatus is the join. Booting DURING the build
# gains nothing: xcodebuild blocks on CoreSimulator until the boot finishes
# (~200 s measured, twice, whatever destination it was given).
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
