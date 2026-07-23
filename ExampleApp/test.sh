#!/bin/sh
# Runs the ExampleApp UI-test suite once on an iPhone simulator. Each test
# launches the app on its own scenario (launchExampleApp sets
# EXAMPLE_SCENARIO per launch), so there is nothing to select here.
set -eu
cd "$(dirname "$0")"

xcodegen generate

xcodebuild test \
    -project ExampleApp.xcodeproj \
    -scheme ExampleApp \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro"
