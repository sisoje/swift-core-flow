#!/bin/sh
# Runs every example scenario's UI tests, one testScenario.sh call at a time.
set -eu
cd "$(dirname "$0")"

sh testScenario.sh GestureState
sh testScenario.sh FocusState
sh testScenario.sh ViewModifier
