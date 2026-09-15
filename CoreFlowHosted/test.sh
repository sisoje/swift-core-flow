#!/bin/sh
# Run the UI tests built by build.sh, no coverage. Each test launches its own
# scenario (launchApp passes a TestPayload per launch). No simulator commands
# here: CI boots the named device before this; standalone, xcodebuild boots
# it itself.
set -eu
cd "$(dirname "$0")"

xcodebuild test-without-building \
    -project CoreFlowHosted.xcodeproj \
    -scheme CoreFlowHostApp \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
    -collect-test-diagnostics never \
    -enableCodeCoverage NO
