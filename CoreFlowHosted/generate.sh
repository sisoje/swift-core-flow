#!/bin/sh
# Rewrites the committed hosted project from scratch with the `xcodeproj` tool
# of Xcode 27.2 beta 3 or later.
set -e
cd "$(dirname "$0")"
project=CoreFlowHosted.xcodeproj
x() { xcrun xcodeproj "$@" -P "$project"; }
rm -rf "$project"
xcrun xcodeproj init "$project"

# Mac Catalyst: a macOS process, so it is signed (ad hoc) without the hardened
# runtime, in the iPad idiom (device family 1,2).
for kv in SDKROOT=iphoneos IPHONEOS_DEPLOYMENT_TARGET=27.0 TARGETED_DEVICE_FAMILY=1,2 SUPPORTS_MACCATALYST=YES MACOSX_DEPLOYMENT_TARGET=27.0 ENABLE_HARDENED_RUNTIME=NO CODE_SIGN_IDENTITY=- SWIFT_VERSION=6.0; do
    x setting set "${kv%%=*}" "${kv#*=}"
done

x target add CoreFlowHostApp --product-type application
x target add CoreFlowHostUITests --product-type ui-test-bundle
x target add-dependency CoreFlowHostUITests CoreFlowHostApp
for t in CoreFlowHostApp CoreFlowHostUITests; do
    for p in sources frameworks; do x target phase add --target $t $p; done
done
x setting set PRODUCT_BUNDLE_IDENTIFIER com.coreflow.hosted.CoreFlowHostApp --target CoreFlowHostApp
x setting set SWIFT_DEFAULT_ACTOR_ISOLATION MainActor --target CoreFlowHostApp
x setting set PRODUCT_BUNDLE_IDENTIFIER com.coreflow.hosted.CoreFlowHostUITests --target CoreFlowHostUITests
x setting set TEST_TARGET_NAME CoreFlowHostApp --target CoreFlowHostUITests

# Folders synchronized with disk: every file in them belongs to the target.
x group add HostApp --filesystem-path HostApp
x group add Shared --filesystem-path Shared
x group add UITests --filesystem-path UITests
x group include --group HostApp --target CoreFlowHostApp
x group include --group Shared --target CoreFlowHostApp
x group include --group Shared --target CoreFlowHostUITests
x group include --group UITests --target CoreFlowHostUITests

x pkg add-local .. --product CoreFlow --target CoreFlowHostApp
x pkg link CoreFlowUITesting --package CoreFlow --target CoreFlowHostUITests

# The one field the tool cannot set: the app is the test host, so Xcode's
# auto-created scheme for the app also builds and runs the UI tests.
sed -i '' 's|"product-type": "bundle.ui-testing",|&\
      "test-host-target": "CoreFlowHostApp",|' "$project/project.xcproj"
