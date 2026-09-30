#!/bin/sh
# Generate the project and build the hosted app + UI-test bundle for Mac
# Catalyst, no coverage. Xcode uses the scheme.
set -eu
cd "$(dirname "$0")"

xcodegen generate

xcodebuild build-for-testing \
    -project CoreFlowHosted.xcodeproj \
    -scheme CoreFlowHostApp \
    -destination "platform=macOS,variant=Mac Catalyst" \
    -enableCodeCoverage NO
