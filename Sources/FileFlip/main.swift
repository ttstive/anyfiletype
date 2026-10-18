import AppKit

// `FileFlip targets <files…>` and `FileFlip convert <format> <files…>` run without UI.
if CommandLine.arguments.count > 1 {
    CLI.run(Array(CommandLine.arguments.dropFirst()))
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
