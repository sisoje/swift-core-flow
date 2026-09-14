#!/bin/sh
# CI entry point for the hosted UI-test suite, no coverage. Each test
# launches its own scenario (launchApp passes a TestPayload per launch).
# Xcode runs the same scheme with its own settings.
set -eu
cd "$(dirname "$0")"

# Boot in the background so the simulator comes up while the build runs:
# on a cold runner the first launch through xcodebuild otherwise timed out
# ("Timed out while launching application via Xcode", 129 s).
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true

xcodegen generate

xcodebuild build-for-testing \
    -project CoreFlowHosted.xcodeproj \
    -scheme CoreFlowHostApp \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
    -enableCodeCoverage NO

xcrun simctl bootstatus "iPhone 17 Pro" -b

xcodebuild test-without-building \
    -project CoreFlowHosted.xcodeproj \
    -scheme CoreFlowHostApp \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
    -collect-test-diagnostics never \
    -enableCodeCoverage NO
