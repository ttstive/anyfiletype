import AppKit

enum CLI {
    static func run(_ args: [String]) -> Never {
        _ = NSApplication.shared  // document conversion uses AppKit printing
        guard let command = args.first else { usage() }
        let rest = Array(args.dropFirst())

        switch command {
        case "targets":
            let files = rest.map { URL(fileURLWithPath: $0) }
            guard !files.isEmpty else { usage() }
            print(Catalog.targets(for: files).map(\.title).joined(separator: " "))
            exit(0)

        case "convert":
            guard rest.count >= 2 else { usage() }
            let format = rest[0]
            let files = rest.dropFirst().map { URL(fileURLWithPath: $0) }
            guard let target = Catalog.targets(for: files).first(where: { $0.title.lowercased() == format.lowercased() }) else {
                fail("Can't convert to \(format). Options: \(Catalog.targets(for: files).map(\.title).joined(separator: ", "))")
            }
            Task { @MainActor in
                do {
                    for out in try await Converter.run(target.op, files: files) { print(out.path) }
                    exit(0)
                } catch {
                    fail(error.localizedDescription)
                }
            }
            RunLoop.main.run()
            exit(0)

        default:
            usage()
        }
    }

    private static func usage() -> Never {
        fail("""
        usage: FileFlip targets <files…>
               FileFlip convert <format> <files…>
        """)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
