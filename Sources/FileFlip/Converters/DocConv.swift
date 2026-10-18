import AppKit

/// Text documents through NSAttributedString. AppKit's readers need the main thread.
@MainActor
enum DocConv {
    static func convert(_ url: URL, to f: DocFormat) throws -> URL {
        let text = try load(url)
        let out = OutputPath.file(for: url, ext: f.rawValue)
        return try OutputPath.producing(out) {
            var attrs: [NSAttributedString.DocumentAttributeKey: Any] = [.documentType: documentType(f)]
            if f == .txt || f == .html {
                attrs[.characterEncoding] = String.Encoding.utf8.rawValue
            }
            let data = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: attrs)
            try data.write(to: out)
            return out
        }
    }

    /// Lays the text out on pages of the default paper size and prints to a PDF.
    static func toPDF(_ url: URL) throws -> URL {
        let text = try load(url)
        let out = OutputPath.file(for: url, ext: "pdf")
        return try OutputPath.producing(out) {
            let info = NSPrintInfo(dictionary: [NSPrintInfo.AttributeKey.jobSavingURL: out])
            info.jobDisposition = .save
            info.paperSize = NSPrintInfo.shared.paperSize
            info.topMargin = 54
            info.bottomMargin = 54
            info.leftMargin = 54
            info.rightMargin = 54
            info.horizontalPagination = .fit
            info.verticalPagination = .automatic
            info.isHorizontallyCentered = false
            info.isVerticallyCentered = false

            let width = info.paperSize.width - info.leftMargin - info.rightMargin
            let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
            view.appearance = NSAppearance(named: .aqua)  // black text even in Dark Mode
            view.isVerticallyResizable = true
            view.textContainer?.widthTracksTextView = true
            view.textStorage?.setAttributedString(text)
            if let container = view.textContainer {
                view.layoutManager?.ensureLayout(for: container)
            }
            view.sizeToFit()

            let op = NSPrintOperation(view: view, printInfo: info)
            op.showsPrintPanel = false
            op.showsProgressPanel = false
            guard op.run() else { throw ConvertError.failed("Couldn't create the PDF.") }
            return out
        }
    }

    private static func load(_ url: URL) throws -> NSAttributedString {
        let ext = Catalog.ext(url)
        if ext == "md" || ext == "markdown" {
            return try markdown(String(contentsOf: url, encoding: .utf8))
        }
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]
        if ext == "txt" {
            options[.documentType] = NSAttributedString.DocumentType.plain
            options[.characterEncoding] = String.Encoding.utf8.rawValue
            options[.defaultAttributes] = [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 12)]
        }
        do {
            return try NSAttributedString(url: url, options: options, documentAttributes: nil)
        } catch {
            throw ConvertError.unreadable(url.lastPathComponent)
        }
    }

    /// Markdown with bold, italic and code kept. Block formatting (headings, lists) stays as plain lines.
    private static func markdown(_ source: String) throws -> NSAttributedString {
        let parsed = try AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
        let base = NSFont.systemFont(ofSize: 12)
        let result = NSMutableAttributedString(string: String(parsed.characters), attributes: [.font: base])
        for run in parsed.runs {
            guard let intent = run.inlinePresentationIntent else { continue }
            let range = NSRange(run.range, in: parsed)
            var font = base
            if intent.contains(.code) {
                font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            }
            var traits: NSFontDescriptor.SymbolicTraits = []
            if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
            if intent.contains(.emphasized) { traits.insert(.italic) }
            if !traits.isEmpty {
                let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
                font = NSFont(descriptor: descriptor, size: font.pointSize) ?? font
            }
            result.addAttribute(.font, value: font, range: range)
        }
        return result
    }

    private static func documentType(_ f: DocFormat) -> NSAttributedString.DocumentType {
        switch f {
        case .docx: return .officeOpenXML
        case .rtf: return .rtf
        case .odt: return .openDocument
        case .html: return .html
        case .txt: return .plain
        case .doc: return .docFormat
        }
    }
}
