#!/bin/sh
# Generate the project, build the hosted app + UI-test bundle as Mac Catalyst
# and run the UI tests on this Mac, no coverage: one xcodebuild, so one
# project load and one package resolution. Each test launches its own
# scenario (launchApp passes a TestPayload per launch). The tests click on
# the real desktop, and macOS must allow it once:
#   sudo automationmodetool enable-automationmode-without-authentication
set -eu
cd "$(dirname "$0")"

xcodegen generate

xcodebuild test \
    -project CoreFlowHosted.xcodeproj \
    -scheme CoreFlowHostApp \
    -destination "platform=macOS,variant=Mac Catalyst" \
    -collect-test-diagnostics never \
    -enableCodeCoverage NO
