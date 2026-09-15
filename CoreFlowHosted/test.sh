#!/bin/sh
# Run the UI tests built by build.sh, no coverage. Each test launches its own
# scenario (launchApp passes a TestPayload per launch). No simulator commands
# here: CI boots the device and passes its UDID as $1 so this targets that
# exact device; with no argument, xcodebuild picks the named device and boots
# it itself.
set -eu
cd "$(dirname "$0")"

device="${1:+id=$1}"

xcodebuild test-without-building \
    -project CoreFlowHosted.xcodeproj \
    -scheme CoreFlowHostApp \
    -destination "platform=iOS Simulator,${device:-name=iPhone 17 Pro}" \
    -collect-test-diagnostics never \
    -enableCodeCoverage NO
