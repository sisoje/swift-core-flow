#!/bin/sh
# Rewrites the committed hosted project from scratch with the `xcodeproj` tool
# of Xcode 27.2 beta 3 or later. The tool finds the one project in this folder.
set -e
cd "$(dirname "$0")"
rm -rf CoreFlowHosted.xcodeproj
xcrun xcodeproj init CoreFlowHosted.xcodeproj

# Project: native macOS, Mac Catalyst, iOS, or visionOS by destination; ad hoc signing,
# no hardened runtime, iPad idiom (device family 1,2).
xcrun xcodeproj setting set SDKROOT auto
xcrun xcodeproj setting set SUPPORTED_PLATFORMS "macosx iphoneos iphonesimulator xros xrsimulator"
xcrun xcodeproj setting set XROS_DEPLOYMENT_TARGET 27.0
xcrun xcodeproj setting set IPHONEOS_DEPLOYMENT_TARGET 27.0
xcrun xcodeproj setting set TARGETED_DEVICE_FAMILY 1,2
xcrun xcodeproj setting set SUPPORTS_MACCATALYST YES
xcrun xcodeproj setting set MACOSX_DEPLOYMENT_TARGET 27.0
xcrun xcodeproj setting set ENABLE_HARDENED_RUNTIME NO
xcrun xcodeproj setting set CODE_SIGN_IDENTITY -
xcrun xcodeproj setting set SWIFT_VERSION 6.0
xcrun xcodeproj setting set PRODUCT_BUNDLE_IDENTIFIER 'com.coreflow.hosted.$(TARGET_NAME)'

# App: HostApp/ and Shared/ synchronized with disk, linking CoreFlow.
xcrun xcodeproj target add CoreFlowHostApp --product-type application
xcrun xcodeproj target phase add sources --target CoreFlowHostApp
xcrun xcodeproj target phase add frameworks --target CoreFlowHostApp
xcrun xcodeproj group add HostApp --filesystem-path HostApp
xcrun xcodeproj group add Shared --filesystem-path Shared
xcrun xcodeproj group include --group HostApp --target CoreFlowHostApp
xcrun xcodeproj group include --group Shared --target CoreFlowHostApp
xcrun xcodeproj pkg add-local .. --product CoreFlow --target CoreFlowHostApp

# UI tests: UITests/ and Shared/, run against the app, linking the log reader.
xcrun xcodeproj target add CoreFlowHostUITests --product-type ui-test-bundle
xcrun xcodeproj target phase add sources --target CoreFlowHostUITests
xcrun xcodeproj target phase add frameworks --target CoreFlowHostUITests
xcrun xcodeproj target add-dependency CoreFlowHostUITests CoreFlowHostApp
xcrun xcodeproj setting set TEST_TARGET_NAME CoreFlowHostApp --target CoreFlowHostUITests
xcrun xcodeproj group add UITests --filesystem-path UITests
xcrun xcodeproj group include --group UITests --target CoreFlowHostUITests
xcrun xcodeproj group include --group Shared --target CoreFlowHostUITests
xcrun xcodeproj pkg link CoreFlowUITesting --package CoreFlow --target CoreFlowHostUITests

# Predictable ids: each target's id is its name; product references need none.
perl -0pi -e 's/"name": "(\w+)",(\s*)"id": "[0-9A-F]{24}"/"name": "$1",$2"id": "$1"/g; s/ "id": "[0-9A-F]{24}",//g' CoreFlowHosted.xcodeproj/project.xcproj
