#!/bin/sh
# Runs the UI-test suite once on an iPhone simulator, against the TEST app
# (@testable import of the UI package, where every component lives). Each
# test launches its own scenario (launchApp sets SCENARIO per launch). The
# real app is the CoreFlowRealApp scheme.
set -eu
cd "$(dirname "$0")"

xcodegen generate

rm -rf TestResults.xcresult
xcodebuild test \
    -project CoreFlowExample.xcodeproj \
    -scheme CoreFlowTestApp \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
    -enableCodeCoverage YES \
    -resultBundlePath TestResults.xcresult \
    -collect-test-diagnostics never

# Which components' scenarios ran — a checklist, not a number (rationale
# in coverage.sh).
sh coverage.sh TestResults.xcresult
