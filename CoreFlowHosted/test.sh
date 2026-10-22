#!/bin/sh
# Hosted UI tests on the destination in $1, default the iPhone 18 Pro
# simulator. A macOS destination clicks on the real desktop; allow it once:
#   sudo automationmodetool enable-automationmode-without-authentication
set -eu
cd "$(dirname "$0")"
result_bundle=CoreFlowHostUITests.xcresult
rm -rf "$result_bundle"

test_status=0
xcodebuild test \
    -project CoreFlowHosted.xcodeproj \
    -scheme CoreFlowHostUITests \
    -destination "${1:-platform=iOS Simulator,name=iPhone 18 Pro}" \
    -resultBundlePath "$result_bundle" \
    -enableCodeCoverage YES \
    -collect-test-diagnostics never || test_status=$?

printf 'Result bundle: %s\n' "$PWD/$result_bundle"
exit "$test_status"
