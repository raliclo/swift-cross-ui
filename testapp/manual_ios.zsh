xcrun simctl boot "swift-cross-ui"
xcrun simctl bootstatus "swift-cross-ui" -b
xcrun simctl install booted /Volumes/Windows/proj_Win/swift-cross-ui/testapp/.bundledApp/debugTarget.app
xcrun simctl launch booted dev.swiftcrossui.testapp.debugTarget