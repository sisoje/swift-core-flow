#!/bin/sh
# Unit and UI tests on the destination in $1, default the iPhone 18 Pro simulator,
# merged into CoreFlow.xcresult. macOS clicks on the real desktop; allow it once:
#   sudo automationmodetool enable-automationmode-without-authentication
set -eu
cd "$(dirname "$0")"
destination=${1:-platform=iOS Simulator,name=iPhone 18 Pro}
rm -rf ./*.xcresult

xcodebuild test -scheme CoreFlow-Package -skip-testing:CoreFlowExpansionTests \
    -destination "$destination" -enableCodeCoverage YES -resultBundlePath Unit.xcresult || status=$?
xcodebuild test -project CoreFlowHosted/CoreFlowHosted.xcodeproj -scheme CoreFlowHostUITests \
    -destination "$destination" -enableCodeCoverage YES -resultBundlePath UI.xcresult || status=$?

xcrun xcresulttool merge Unit.xcresult UI.xcresult --output-path CoreFlow.xcresult
rm -rf Unit.xcresult UI.xcresult
echo "Result bundle: $PWD/CoreFlow.xcresult"
exit "${status-0}"
