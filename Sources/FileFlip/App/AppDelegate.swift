import AppKit
import Carbon.HIToolbox
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private var panel: CarouselPanel?
    private let launchItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")

    static let shortcutLabel = "⌃⌥T"

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpMenuBar()
        hotKey = HotKey(keyCode: kVK_ANSI_T, modifiers: controlKey | optionKey) { [weak self] in
            MainActor.assumeIsolated { self?.trigger() }
        }
        if hotKey?.isRegistered != true {
            alert("\(Self.shortcutLabel) is already taken",
                  "Another app registered this shortcut. You can still use FileFlip from the menu bar.")
        }
    }

    private func setUpMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "FileFlip")

        let menu = NSMenu()
        let convert = NSMenuItem(title: "Convert Finder Selection", action: #selector(convertSelection), keyEquivalent: "t")
        convert.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(convert)
        menu.addItem(NSMenuItem(title: "Choose Files…", action: #selector(chooseFiles), keyEquivalent: ""))
        menu.addItem(.separator())
        let ffmpeg = NSMenuItem(title: FFmpeg.isAvailable ? "FFmpeg: installed (extra formats on)"
                                                         : "FFmpeg: not installed (brew install ffmpeg)",
                                action: nil, keyEquivalent: "")
        ffmpeg.isEnabled = false
        menu.addItem(ffmpeg)
        launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit FileFlip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for entry in menu.items where entry.action != #selector(NSApplication.terminate(_:)) {
            entry.target = self
        }
        item.menu = menu
        statusItem = item
    }

    /// Shortcut pressed: convert the Finder selection, or ask for files when Finder isn't in front.
    private func trigger() {
        if let panel, panel.isVisible {
            panel.dismiss()
            return
        }
        if FinderSelection.finderIsFrontmost {
            convertSelection()
        } else {
            chooseFiles()
        }
    }

    @objc private func convertSelection() {
        switch FinderSelection.get() {
        case .success(let urls) where !urls.isEmpty:
            show(urls)
        case .success:
            chooseFiles()
        case .failure(.notAllowed):
            alert("Allow FileFlip to control Finder",
                  "Open System Settings → Privacy & Security → Automation, and turn on Finder under FileFlip.")
        case .failure(.other(let message)):
            alert("Couldn't read the Finder selection", message)
        }
    }

    @objc private func chooseFiles() {
        NSApp.activate(ignoringOtherApps: true)
        let picker = NSOpenPanel()
        picker.allowsMultipleSelection = true
        picker.canChooseDirectories = true
        picker.prompt = "Convert"
        if picker.runModal() == .OK, !picker.urls.isEmpty {
            show(picker.urls)
        }
    }

    private func show(_ urls: [URL]) {
        panel?.dismiss()
        let panel = CarouselPanel(model: CarouselModel(files: urls))
        panel.onClose = { [weak self, weak panel] in
            if self?.panel === panel { self?.panel = nil }
        }
        self.panel = panel
        panel.present()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            alert("Couldn't change Open at Login", error.localizedDescription)
        }
        launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
