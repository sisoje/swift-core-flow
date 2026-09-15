#!/bin/sh
# Run the UI tests built by build.sh on the simulator named by $1, no
# coverage. Each test launches its own scenario (launchApp passes a
# TestPayload per launch). No simulator commands here: CI boots that device
# before this; standalone, xcodebuild boots it itself.
#   sh test.sh "iPhone 17 Pro"
set -eu
cd "$(dirname "$0")"

xcodebuild test-without-building \
    -project CoreFlowHosted.xcodeproj \
    -scheme CoreFlowHostApp \
    -destination "platform=iOS Simulator,name=$1" \
    -collect-test-diagnostics never \
    -enableCodeCoverage NO
