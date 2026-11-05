import Foundation

// The app's entry point. It sets one AppKit switch before AppKit reads the command line, then starts the SwiftUI app.
// (LaunchArguments.swift explains why: a developer flag with no value, like --lock, used to stop the app from launching.)
LaunchArguments.stopTreatingStrayArgumentsAsFiles()
FontDropApp.main()
