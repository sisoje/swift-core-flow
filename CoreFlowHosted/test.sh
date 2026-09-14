#!/bin/sh
# CI entry point for the hosted UI-test suite: three simulator clones in
# parallel, no coverage. Each test launches its own scenario (launchApp
# passes a TestPayload per launch). Xcode runs the same scheme with its own
# settings.
set -eu
cd "$(dirname "$0")"

xcodegen generate

# Boot first: on a cold CI runner the first launch through xcodebuild timed
# out ("Timed out while launching application via Xcode", 129 s), failing
# whichever test ran first while every later launch succeeded.
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
xcrun simctl bootstatus "iPhone 17 Pro" -b

xcodebuild test \
    -project CoreFlowHosted.xcodeproj \
    -scheme CoreFlowHostApp \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
    -collect-test-diagnostics never \
    -parallel-testing-enabled YES \
    -parallel-testing-worker-count 3 \
    -enableCodeCoverage NO
