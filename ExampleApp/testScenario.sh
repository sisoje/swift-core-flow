#!/bin/sh
# Runs the whole ExampleAppUITests target on an iPhone 17 Pro simulator.
# <ScenarioName> becomes TEST_RUNNER_EXAMPLE_SCENARIO for xcodebuild
# (verified directly — xcodebuild strips the TEST_RUNNER_ prefix; a plain
# EXAMPLE_SCENARIO=... export does NOT reach the test process), then
# EXAMPLE_SCENARIO for the ExampleApp process if launched directly (Cmd-R)
# with that scheme env var configured. Each UI test sets its own scenario
# explicitly via launchExampleApp(scenario:) (UITests/LaunchHelper.swift), so
# this argument has no effect on which tests run or pass — see testAll.sh.
set -eu
cd "$(dirname "$0")"

if [ $# -ne 1 ]; then
    echo "usage: $0 <ScenarioName>" >&2
    exit 1
fi
scenario="$1"

xcodegen generate

env "TEST_RUNNER_EXAMPLE_SCENARIO=$scenario" xcodebuild test \
    -project ExampleApp.xcodeproj \
    -scheme ExampleApp \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro"
