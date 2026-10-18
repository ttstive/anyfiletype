import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ImageConv {
    private static let writableTypes: Set<String> =
        Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])

    static func canWrite(_ f: ImageFormat) -> Bool {
        writableTypes.contains(f.type.identifier)
    }

    static func convert(_ url: URL, to f: ImageFormat) throws -> URL {
        let (image, props) = try load(url)
        let out = OutputPath.file(for: url, ext: f.ext)
        return try OutputPath.producing(out) {
            let final = f.keepsAlpha ? image : flatten(image)
            var options = props
            if f == .jpeg || f == .heic || f == .webp {
                options[kCGImageDestinationLossyCompressionQuality as String] = 0.9
            }
            try write(final, to: out, type: f.type, properties: options)
            return out
        }
    }

    static func toPDF(_ url: URL) throws -> URL {
        let image = try loadOriented(url)
        let out = OutputPath.file(for: url, ext: "pdf")
        return try OutputPath.producing(out) {
            var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            guard let ctx = CGContext(out as CFURL, mediaBox: &box, nil) else {
                throw ConvertError.failed("Couldn't create the PDF.")
            }
            ctx.beginPDFPage(nil)
            ctx.draw(image, in: box)
            ctx.endPDFPage()
            ctx.closePDF()
            return out
        }
    }

    static func write(_ image: CGImage, to out: URL, type: UTType, properties: [String: Any] = [:]) throws {
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConvertError.failed("This Mac can't write \(type.preferredFilenameExtension ?? "that format").")
        }
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ConvertError.failed("Couldn't save \(out.lastPathComponent).")
        }
    }

    /// First frame plus its metadata (metadata keeps EXIF orientation intact).
    private static func load(_ url: URL) throws -> (CGImage, [String: Any]) {
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           CGImageSourceGetCount(src) > 0,
           let image = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            let props = (CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any]) ?? [:]
            return (image, props)
        }
        // NSImage handles a few formats ImageIO can't, such as SVG.
        if let ns = NSImage(contentsOf: url), let image = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return (image, [:])
        }
        throw ConvertError.unreadable(url.lastPathComponent)
    }

    /// Image with EXIF rotation applied to the pixels, for formats without orientation tags.
    private static func loadOriented(_ url: URL) throws -> CGImage {
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(src) > 0 {
            let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any]
            let w = props?[kCGImagePropertyPixelWidth as String] as? Int ?? 4096
            let h = props?[kCGImagePropertyPixelHeight as String] as? Int ?? 4096
            let opts: [String: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways as String: true,
                kCGImageSourceCreateThumbnailWithTransform as String: true,
                kCGImageSourceThumbnailMaxPixelSize as String: max(w, h),
            ]
            if let image = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) {
                return image
            }
        }
        return try load(url).0
    }

    /// Puts transparent images on white, for formats without an alpha channel.
    private static func flatten(_ image: CGImage) -> CGImage {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return image
        default: break
        }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return image }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        return ctx.makeImage() ?? image
    }
}
