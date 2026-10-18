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
        case .done: revealOutputs()
        case .failed: close()
        case .working: break
        }
    }

    func revealOutputs() {
        guard case .done(let outputs) = state else { return }
        NSWorkspace.shared.activateFileViewerSelecting(outputs)
        close()
    }

    private func start() {
        guard let target = selected else { return }
        UserDefaults.standard.set(target.title, forKey: memoryKey)
        state = .working(target.title)
        Task {
            do {
                let outputs = try await Converter.run(target.op, files: files)
                Recents.add(outputs)
                state = .done(outputs)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}

/// The last conversions, newest first, for the menu bar's Recent list.
enum Recents {
    private static let key = "recentOutputs"
    private static let limit = 10

    static var all: [URL] {
        (UserDefaults.standard.stringArray(forKey: key) ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func add(_ urls: [URL]) {
        let paths = urls.map(\.path) + (UserDefaults.standard.stringArray(forKey: key) ?? [])
        var seen = Set<String>()
        let unique = paths.filter { seen.insert($0).inserted }
        UserDefaults.standard.set(Array(unique.prefix(limit)), forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
