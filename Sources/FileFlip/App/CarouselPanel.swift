import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Floating, borderless panel that takes keys without activating the app,
/// so Finder stays the frontmost app underneath (like Spotlight).
@MainActor
final class CarouselPanel: NSPanel {
    let model: CarouselModel
    var onClose: () -> Void = {}

    private var monitor: Any?
    private var scrollAccumulator: CGFloat = 0
    private var typed = ""
    private var lastTyped = Date.distantPast

    init(model: CarouselModel) {
        self.model = model
        super.init(contentRect: NSRect(x: 0, y: 0, width: 660, height: 330),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let host = NSHostingView(rootView: CarouselView(model: model))
        host.frame = contentRect(forFrameRect: frame)
        contentView = host
        setContentSize(host.fittingSize)

        model.close = { [weak self] in self?.dismiss() }
    }

    override var canBecomeKey: Bool { true }

    func present() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            setFrameOrigin(NSPoint(x: area.midX - frame.width / 2,
                                   y: area.midY - frame.height / 2 + area.height * 0.08))
        }
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; animator().alphaValue = 1 }

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel]) { [weak self] event in
            guard let self, event.window === self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    func dismiss() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        orderOut(nil)
        onClose()
    }

    /// Clicking elsewhere closes the carousel only while picking a format.
    /// Once a conversion starts, it stays until you choose Show in Finder or Close.
    override func resignKey() {
        super.resignKey()
        if model.state == .choosing { dismiss() }
    }

    private func handle(_ event: NSEvent) -> Bool {
        if event.type == .scrollWheel {
            scroll(event)
            return true
        }
        switch Int(event.keyCode) {
        case kVK_LeftArrow, kVK_UpArrow: model.move(-1)
        case kVK_RightArrow, kVK_DownArrow: model.move(1)
        case kVK_Tab: model.move(event.modifierFlags.contains(.shift) ? -1 : 1)
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Space: model.confirm()
        case kVK_Escape: dismiss()
        default:
            guard let chars = event.charactersIgnoringModifiers, chars.allSatisfy(\.isLetter) || chars.allSatisfy(\.isNumber),
                  !chars.isEmpty else { return false }
            if Date().timeIntervalSince(lastTyped) > 0.8 { typed = "" }
            typed += chars
            lastTyped = Date()
            model.jump(to: typed)
        }
        return true
    }

    /// Trackpad swipes and mouse wheels both step through formats.
    private func scroll(_ event: NSEvent) {
        guard event.momentumPhase.isEmpty else { return }  // ignore inertia so it stops where you stop
        let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        let delta = -(abs(dx) > abs(dy) ? dx : dy)
        if !event.hasPreciseScrollingDeltas {
            if delta != 0 { model.move(delta > 0 ? 1 : -1) }
            return
        }
        if event.phase == .began { scrollAccumulator = 0 }
        scrollAccumulator += delta
        let step: CGFloat = 28
        while abs(scrollAccumulator) >= step {
            model.move(scrollAccumulator > 0 ? 1 : -1)
            scrollAccumulator -= scrollAccumulator > 0 ? step : -step
        }
    }
}
