import Foundation
import PDFKit

enum PDFConv {
    /// One image per page. Multi-page PDFs go into a new folder.
    static func toImages(_ url: URL, format f: ImageFormat) throws -> [URL] {
        guard let doc = CGPDFDocument(url as CFURL), doc.numberOfPages > 0 else {
            throw ConvertError.unreadable(url.lastPathComponent)
        }
        let base = url.deletingPathExtension().lastPathComponent
        let count = doc.numberOfPages

        if count == 1, let page = doc.page(at: 1) {
            let out = OutputPath.file(for: url, ext: f.ext)
            try OutputPath.producing(out) { try ImageConv.write(render(page), to: out, type: f.type, properties: quality(f)) }
            return [out]
        }

        let folder = OutputPath.folder(in: url.deletingLastPathComponent(), named: "\(base) (\(f.title))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try OutputPath.producing(folder) {
            let digits = String(count).count
            for i in 1...count {
                guard let page = doc.page(at: i) else { continue }
                let number = String(repeating: "0", count: max(0, digits - String(i).count)) + String(i)
                let out = folder.appendingPathComponent("\(base)-\(number)").appendingPathExtension(f.ext)
                try ImageConv.write(render(page), to: out, type: f.type, properties: quality(f))
            }
        }
        return [folder]
    }

    static func toText(_ url: URL) throws -> URL {
        guard let doc = PDFDocument(url: url) else { throw ConvertError.unreadable(url.lastPathComponent) }
        let text = doc.string ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ConvertError.failed("This PDF has no selectable text (it may be a scan).")
        }
        let out = OutputPath.file(for: url, ext: "txt")
        try text.write(to: out, atomically: true, encoding: .utf8)
        return out
    }

    private static func quality(_ f: ImageFormat) -> [String: Any] {
        f == .jpeg ? [kCGImageDestinationLossyCompressionQuality as String: 0.9] : [:]
    }

    /// Renders a page at 2x (144 dpi) on white, honoring page rotation.
    private static func render(_ page: CGPDFPage, scale: CGFloat = 2) throws -> CGImage {
        let box = page.getBoxRect(.cropBox)
        let rotated = page.rotationAngle % 180 != 0
        let size = rotated ? CGSize(width: box.height, height: box.width) : box.size
        let w = Int(size.width * scale), h = Int(size.height * scale)
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw ConvertError.failed("Couldn't render the PDF page.") }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        ctx.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size),
                                                 rotate: 0, preserveAspectRatio: true))
        ctx.drawPDFPage(page)
        guard let image = ctx.makeImage() else { throw ConvertError.failed("Couldn't render the PDF page.") }
        return image
    }
}
