#!/bin/sh
# Runs the GestureState example scenario's UI tests (DragCard + TrickyDragCard)
# on an iPhone 17 Pro simulator. TEST_RUNNER_EXAMPLE_SCENARIO becomes
# EXAMPLE_SCENARIO inside the test process (xcodebuild strips the
# TEST_RUNNER_ prefix — verified directly; a plain EXAMPLE_SCENARIO=... export
# does NOT reach it), which UITests/LaunchHelper.swift then forwards into the
# app under test's own launchEnvironment.
set -eu
cd "$(dirname "$0")"

xcodegen generate

TEST_RUNNER_EXAMPLE_SCENARIO=GestureState xcodebuild test \
    -project ExampleApp.xcodeproj \
    -scheme ExampleApp \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro"
