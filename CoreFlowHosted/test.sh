#!/bin/sh
# Runs the hosted UI-test suite once on an iPhone simulator. Each test
# launches its own scenario (launchApp sets SCENARIO per launch).
set -eu
cd "$(dirname "$0")"

xcodegen generate

xcodebuild test \
    -project CoreFlowHosted.xcodeproj \
    -scheme CoreFlowHostApp \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
    -collect-test-diagnostics never
