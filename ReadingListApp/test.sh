#!/bin/sh
# Runs the UI-test suite once on an iPhone simulator, against the TEST app
# (@testable import of the UI package). Each test launches its own scenario
# (launchApp sets SCENARIO per launch). The real app is the ReadingList scheme.
set -eu
cd "$(dirname "$0")"

xcodegen generate

xcodebuild test \
    -project ReadingList.xcodeproj \
    -scheme ReadingListTestApp \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro"
