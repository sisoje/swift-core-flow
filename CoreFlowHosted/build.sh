#!/bin/sh
# Generate the project and build the hosted app + UI-test bundle for the
# simulator, no coverage. No simulator commands here: CI boots the device
# around this script, locally boot what you like. Xcode uses the scheme.
set -eu
cd "$(dirname "$0")"

xcodegen generate

xcodebuild build-for-testing \
    -project CoreFlowHosted.xcodeproj \
    -scheme CoreFlowHostApp \
    -destination "generic/platform=iOS Simulator" \
    -enableCodeCoverage NO
