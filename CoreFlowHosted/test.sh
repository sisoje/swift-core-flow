#!/bin/sh
# Run the UI tests built by build.sh as Mac Catalyst on this Mac, no
# coverage. Each test launches its own scenario (launchApp passes a
# TestPayload per launch). The tests click on the real desktop, and macOS
# must allow it once:
#   sudo automationmodetool enable-automationmode-without-authentication
set -eu
cd "$(dirname "$0")"

# From the .xctestrun build.sh produced, not from the project: xcodebuild
# then loads no project and does not resolve the packages a second time.
xctestrun=$(ls -t ~/Library/Developer/Xcode/DerivedData/CoreFlowHosted-*/Build/Products/CoreFlowHostApp_macosx*.xctestrun | head -1)

xcodebuild test-without-building \
    -xctestrun "$xctestrun" \
    -destination "platform=macOS,variant=Mac Catalyst" \
    -collect-test-diagnostics never
