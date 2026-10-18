import AppKit

enum FinderSelection {
    enum Failure: Error {
        case notAllowed
        case other(String)
    }

    static var finderIsFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
    }

    /// Files selected in the front Finder window (or on the Desktop).
    @MainActor
    static func get() -> Result<[URL], Failure> {
        let source = """
        tell application "Finder"
            set picked to selection as alias list
            set paths to {}
            repeat with f in picked
                set end of paths to POSIX path of f
            end repeat
            return paths
        end tell
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return .failure(.other("Script error")) }
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int
            if code == -1743 { return .failure(.notAllowed) }
            return .failure(.other(error[NSAppleScript.errorMessage] as? String ?? "Finder didn't answer."))
        }
        guard result.numberOfItems > 0 else { return .success([]) }
        let urls = (1...result.numberOfItems).compactMap { i -> URL? in
            guard let path = result.atIndex(i)?.stringValue else { return nil }
            return URL(fileURLWithPath: path)
        }
        return .success(urls)
    }
}
