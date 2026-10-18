import AppKit

@MainActor
final class CarouselModel: ObservableObject {
    enum State: Equatable {
        case choosing
        case working(String)
        case done([URL])
        case failed(String)
    }

    let files: [URL]
    let targets: [Target]
    @Published var index: Int
    @Published var state: State = .choosing
    var close: () -> Void = {}

    private let memoryKey: String

    init(files: [URL]) {
        self.files = files
        self.targets = Catalog.targets(for: files)
        let kind = files.first.map(Catalog.kind(of:))?.rawValue ?? "none"
        memoryKey = "lastTarget.\(kind)"
        // Start on the format picked last time for this kind of file.
        let last = UserDefaults.standard.string(forKey: memoryKey)
        index = targets.firstIndex { $0.title == last } ?? 0
    }

    var selected: Target? { targets.indices.contains(index) ? targets[index] : nil }

    func move(_ delta: Int) {
        guard state == .choosing, !targets.isEmpty else { return }
        index = min(max(index + delta, 0), targets.count - 1)
    }

    func select(_ i: Int) {
        guard state == .choosing, targets.indices.contains(i) else { return }
        if i == index { confirm() } else { index = i }
    }

    /// Jumps to the first format whose name starts with the typed letters.
    func jump(to prefix: String) {
        guard state == .choosing else { return }
        if let i = targets.firstIndex(where: { $0.title.lowercased().hasPrefix(prefix.lowercased()) }) {
            index = i
        }
    }

    func confirm() {
        switch state {
        case .choosing: start()
        case .done(let outputs):
            NSWorkspace.shared.activateFileViewerSelecting(outputs)
            close()
        case .failed: close()
        case .working: break
        }
    }

    private func start() {
        guard let target = selected else { return }
        UserDefaults.standard.set(target.title, forKey: memoryKey)
        state = .working(target.title)
        Task {
            do {
                let outputs = try await Converter.run(target.op, files: files)
                state = .done(outputs)
                try? await Task.sleep(for: .seconds(2))
                if case .done = state { close() }
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}
