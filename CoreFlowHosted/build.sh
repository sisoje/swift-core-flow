#!/bin/sh
# Build the hosted app + UI-test bundle for the destination in $1 (default native
# macOS), no coverage. Xcode uses the scheme. The project comes from generate.sh.
set -eu
cd "$(dirname "$0")"

xcodebuild build-for-testing \
    -project CoreFlowHosted.xcodeproj \
    -scheme CoreFlowHostUITests \
    -destination "${1:-platform=macOS}" \
    -enableCodeCoverage NO
