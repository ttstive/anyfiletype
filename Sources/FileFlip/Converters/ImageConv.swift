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

    /// Resized copy next to the original. PNGs stay PNG (keeps transparency); everything else becomes JPG,
    /// which every app accepts for uploads. Images are never enlarged.
    static func resize(_ url: URL, _ mode: ResizeMode) throws -> URL {
        let source = try loadOriented(url)
        let w = CGFloat(source.width), h = CGFloat(source.height)
        let keepPNG = Catalog.ext(url) == "png" && !isMaxBytes(mode)
        let format: ImageFormat = keepPNG ? .png : .jpeg
        let out = OutputPath.file(for: url, ext: format.ext, suffix: mode.suffix)

        return try OutputPath.producing(out) {
            switch mode {
            case .square(let n):
                let side = min(w, h)
                let crop = CGRect(x: ((w - side) / 2).rounded(.down), y: ((h - side) / 2).rounded(.down),
                                  width: side, height: side)
                let target = min(CGFloat(n), side)
                let image = try draw(source, crop: crop, size: CGSize(width: target, height: target), opaque: !keepPNG)
                try write(image, to: out, type: format.type, properties: quality(0.9, format))

            case .maxEdge(let n):
                let factor = min(1, CGFloat(n) / max(w, h))
                let image = try draw(source, crop: nil, size: CGSize(width: w * factor, height: h * factor), opaque: !keepPNG)
                try write(image, to: out, type: format.type, properties: quality(0.9, format))

            case .scale(let f):
                let factor = min(1, CGFloat(f))
                let image = try draw(source, crop: nil, size: CGSize(width: w * factor, height: h * factor), opaque: !keepPNG)
                try write(image, to: out, type: format.type, properties: quality(0.9, format))

            case .maxBytes(let limit):
                try jpeg(from: source, under: limit).write(to: out)
            }
            return out
        }
    }

    private static func isMaxBytes(_ mode: ResizeMode) -> Bool {
        if case .maxBytes = mode { return true }
        return false
    }

    private static func quality(_ q: Double, _ f: ImageFormat) -> [String: Any] {
        f == .jpeg ? [kCGImageDestinationLossyCompressionQuality as String: q] : [:]
    }

    /// Lowers JPEG quality, then size, until the file fits.
    private static func jpeg(from source: CGImage, under limit: Int) throws -> Data {
        var image = try draw(source, crop: nil, size: CGSize(width: source.width, height: source.height), opaque: true)
        for _ in 0..<12 {
            for q in [0.85, 0.75, 0.65, 0.55] {
                let data = try encode(image, quality: q)
                if data.count <= limit { return data }
            }
            let size = CGSize(width: CGFloat(image.width) * 0.8, height: CGFloat(image.height) * 0.8)
            guard size.width >= 16, size.height >= 16 else { break }
            image = try draw(image, crop: nil, size: size, opaque: true)
        }
        throw ConvertError.failed("Couldn't get the image under \(limit / 1_000_000) MB.")
    }

    private static func encode(_ image: CGImage, quality: Double) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ConvertError.failed("Couldn't encode the image.")
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality as String: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ConvertError.failed("Couldn't encode the image.") }
        return data as Data
    }

    /// High-quality crop and scale. Opaque output gets a white background.
    private static func draw(_ image: CGImage, crop: CGRect?, size: CGSize, opaque: Bool) throws -> CGImage {
        let source = crop.flatMap { image.cropping(to: $0) } ?? image
        let width = max(1, Int(size.width.rounded())), height = max(1, Int(size.height.rounded()))
        let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: info)
        else { throw ConvertError.failed("Couldn't resize the image.") }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        if opaque {
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(rect)
        }
        ctx.interpolationQuality = .high
        ctx.draw(source, in: rect)
        guard let result = ctx.makeImage() else { throw ConvertError.failed("Couldn't resize the image.") }
        return result
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
