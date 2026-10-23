#!/bin/sh
# Unit and UI tests on the destination in $1, default the iPhone 18 Pro simulator,
# merged into CoreFlow.xcresult, and CoreFlow's coverage into CoreFlow.lcov, read
# from the profile data: the xcresult drops a package target's files at random.
# macOS clicks on the real desktop; allow it once:
#   sudo automationmodetool enable-automationmode-without-authentication
set -eu
cd "$(dirname "$0")"
destination=${1:-platform=iOS Simulator,name=iPhone 18 Pro}
derived=~/Library/Developer/Xcode/DerivedData
# Every ProfileData goes first, so the ones left afterwards are the two runs' own.
rm -rf ./*.xcresult "$derived"/*/Build/ProfileData

xcodebuild test -scheme CoreFlow-Package -skip-testing:CoreFlowExpansionTests \
    -destination "$destination" -enableCodeCoverage YES -resultBundlePath Unit.xcresult || status=$?
xcodebuild test -project CoreFlowHosted/CoreFlowHosted.xcodeproj -scheme CoreFlowHostUITests \
    -destination "$destination" -enableCodeCoverage YES -resultBundlePath UI.xcresult || status=$?

xcrun xcresulttool merge Unit.xcresult UI.xcresult --output-path CoreFlow.xcresult
rm -rf Unit.xcresult UI.xcresult

xcrun llvm-profdata merge -o CoreFlow.profdata "$derived"/*/Build/ProfileData/*/Coverage.profdata
objects=$(find "$derived"/*/Build/ProfileData/../Products -type f \
    \( -path '*.xctest/*' -name CoreFlowTests -o -path '*.app/*' -name CoreFlowHostApp \) | sed 's/^/-object /')
xcrun llvm-cov export -format=lcov -instr-profile CoreFlow.profdata $objects -sources Sources/CoreFlow |
    sed "s#^SF:$PWD/#SF:#" > CoreFlow.lcov
# llvm-cov ignores a -sources path that matches nothing and exports everything; fail instead.
if grep '^SF:' CoreFlow.lcov | grep -v '^SF:Sources/CoreFlow/'; then
    echo "CoreFlow.lcov reaches outside Sources/CoreFlow" >&2
    exit 1
fi
xcrun llvm-cov report -instr-profile CoreFlow.profdata $objects -sources Sources/CoreFlow
echo "Result bundle: $PWD/CoreFlow.xcresult"
exit "${status-0}"
