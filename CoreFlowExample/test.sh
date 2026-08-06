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

# Raw per-target table plus the adjusted table (host members excluded —
# they execute as Core's macro-generated copies, invisible to coverage
# attribution; rationale in coverage.sh).
sh coverage.sh TestResults.xcresult
