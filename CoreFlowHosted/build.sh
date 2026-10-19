#!/bin/sh
# Build the hosted app + UI-test bundle for Mac Catalyst, no coverage. Xcode
# uses the scheme. The project comes from generate.sh.
set -eu
cd "$(dirname "$0")"

xcodebuild build-for-testing \
    -project CoreFlowHosted.xcodeproj \
    -scheme CoreFlowHostUITests \
    -destination "platform=macOS,variant=Mac Catalyst" \
    -enableCodeCoverage NO
