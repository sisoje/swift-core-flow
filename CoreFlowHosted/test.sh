#!/bin/sh
# Run the UI tests built by build.sh as Mac Catalyst on this Mac, no
# coverage. Each test launches its own scenario (launchApp passes a
# TestPayload per launch). The tests click on the real desktop, and macOS
# must allow it once:
#   sudo automationmodetool enable-automationmode-without-authentication
set -eu
cd "$(dirname "$0")"

xcodebuild test-without-building \
    -project CoreFlowHosted.xcodeproj \
    -scheme CoreFlowHostApp \
    -destination "platform=macOS,variant=Mac Catalyst" \
    -collect-test-diagnostics never \
    -enableCodeCoverage NO
