#!/bin/sh
# Runs the ExampleApp UI-test suite once on an iPhone simulator. Each test
# launches the app on its own scenario (launchExampleApp/SnapshotTestCase
# set EXAMPLE_SCENARIO per launch), so there is nothing to select here.
# Snapshot tests: first run records Snapshots/<test>.txt and skips; later
# runs compare. Delete a snapshot file to re-record it.
set -eu
cd "$(dirname "$0")"

xcodegen generate

xcodebuild test \
    -project ExampleApp.xcodeproj \
    -scheme ExampleApp \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro"
