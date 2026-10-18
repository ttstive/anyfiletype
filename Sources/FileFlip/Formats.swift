import Foundation
import UniformTypeIdentifiers

enum ImageFormat: String, CaseIterable, Hashable {
    case png, jpeg, heic, tiff, gif, bmp, webp

    var ext: String { self == .jpeg ? "jpg" : rawValue }
    var title: String { self == .jpeg ? "JPG" : rawValue.uppercased() }
    var keepsAlpha: Bool { self != .jpeg && self != .bmp }

    var type: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        case .tiff: return .tiff
        case .gif: return .gif
        case .bmp: return .bmp
        case .webp: return .webP
        }
    }
}

enum DocFormat: String, CaseIterable, Hashable {
    case docx, rtf, odt, html, txt, doc
}

enum VideoFormat: String, CaseIterable, Hashable {
    case mp4, mov, m4v
}

enum AudioFormat: String, CaseIterable, Hashable {
    case m4a, wav, aiff, caf
}

/// One conversion the app knows how to run.
enum Op: Hashable {
    case image(ImageFormat)
    case imageToPDF
    case pdfToImage(ImageFormat)
    case pdfToText
    case document(DocFormat)
    case documentToPDF
    case video(VideoFormat)
    case audioExtract
    case videoToGIF
    case audio(AudioFormat)
    case ffmpeg(String)
    case zip
    case unzip
}

/// A card in the carousel.
struct Target: Identifiable, Hashable {
    let op: Op
    let title: String
    let caption: String
    let symbol: String
    var id: Op { op }
}

enum SourceKind: String {
    case image, pdf, document, video, audio, zip, folder, other
}

enum Catalog {
    static let documentExts: Set<String> = ["docx", "doc", "rtf", "odt", "html", "txt", "md", "markdown"]
    static let nativeVideoExts: Set<String> = ["mov", "mp4", "m4v", "3gp", "qt"]
    static let otherVideoExts: Set<String> = ["mkv", "webm", "avi", "flv", "wmv", "mpg", "mpeg", "ts", "m2ts", "ogv"]
    static let nativeAudioExts: Set<String> = ["m4a", "mp3", "wav", "aiff", "caf", "aac", "flac"]
    static let otherAudioExts: Set<String> = ["ogg", "opus", "wma"]

    /// Lowercased extension with common aliases folded together.
    static func ext(_ url: URL) -> String {
        let e = url.pathExtension.lowercased()
        switch e {
        case "jpeg": return "jpg"
        case "tif": return "tiff"
        case "htm": return "html"
        case "text": return "txt"
        case "aif": return "aiff"
        default: return e
        }
    }

    static func kind(of url: URL) -> SourceKind {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if isDir { return .folder }
        let e = ext(url)
        if e == "zip" { return .zip }
        if e == "pdf" { return .pdf }
        if documentExts.contains(e) { return .document }
        if nativeVideoExts.contains(e) || otherVideoExts.contains(e) { return .video }
        if nativeAudioExts.contains(e) || otherAudioExts.contains(e) { return .audio }
        if let t = UTType(filenameExtension: e), t.conforms(to: .image) { return .image }
        return .other
    }

    static func targets(for url: URL) -> [Target] {
        let e = ext(url)
        let ff = FFmpeg.isAvailable
        let kind = kind(of: url)
        var list: [Target] = []
        func add(_ op: Op, _ title: String, _ caption: String, _ symbol: String) {
            list.append(Target(op: op, title: title, caption: caption, symbol: symbol))
        }

        switch kind {
        case .image:
            for f in ImageFormat.allCases where f.ext != e {
                if ImageConv.canWrite(f) {
                    add(.image(f), f.title, "Image", "photo")
                } else if f == .webp && ff {
                    add(.ffmpeg("webp"), "WEBP", "Image", "photo")
                }
            }
            add(.imageToPDF, "PDF", "Document", "doc.richtext")

        case .pdf:
            add(.pdfToImage(.png), "PNG", "Pages as images", "photo.on.rectangle")
            add(.pdfToImage(.jpeg), "JPG", "Pages as images", "photo.on.rectangle")
            add(.pdfToText, "TXT", "Plain text", "text.alignleft")

        case .document:
            add(.documentToPDF, "PDF", "Document", "doc.richtext")
            for f in DocFormat.allCases where f.rawValue != e {
                add(.document(f), f.rawValue.uppercased(), f == .txt ? "Plain text" : "Document", "doc.text")
            }

        case .video:
            if nativeVideoExts.contains(e) {
                for f in VideoFormat.allCases where f.rawValue != e {
                    add(.video(f), f.rawValue.uppercased(), "Video", "film")
                }
                add(.videoToGIF, "GIF", "Animation", "photo.stack")
                add(.audioExtract, "M4A", "Audio only", "waveform")
                if ff {
                    add(.ffmpeg("webm"), "WEBM", "Video", "film")
                    add(.ffmpeg("mkv"), "MKV", "Video", "film")
                    add(.ffmpeg("mp3"), "MP3", "Audio only", "waveform")
                }
            } else if ff {
                for v in ["mp4", "mov", "webm", "mkv"] where v != e {
                    add(.ffmpeg(v), v.uppercased(), "Video", "film")
                }
                add(.ffmpeg("gif"), "GIF", "Animation", "photo.stack")
                add(.ffmpeg("mp3"), "MP3", "Audio only", "waveform")
                add(.ffmpeg("m4a"), "M4A", "Audio only", "waveform")
            }

        case .audio:
            if nativeAudioExts.contains(e) {
                for f in AudioFormat.allCases where f.rawValue != e {
                    add(.audio(f), f.rawValue.uppercased(), "Audio", "music.note")
                }
                if ff {
                    for a in ["mp3", "flac", "ogg"] where a != e {
                        add(.ffmpeg(a), a.uppercased(), "Audio", "music.note")
                    }
                }
            } else if ff {
                for a in ["mp3", "m4a", "wav", "flac", "ogg"] where a != e {
                    add(.ffmpeg(a), a.uppercased(), "Audio", "music.note")
                }
            }

        case .zip:
            add(.unzip, "Extract", "Unpack here", "archivebox")

        case .folder, .other:
            break
        }

        if kind != .zip {
            add(.zip, "ZIP", "Compress", "doc.zipper")
        }
        return list
    }

    /// Targets every selected file supports, in the first file's order.
    static func targets(for urls: [URL]) -> [Target] {
        guard let first = urls.first else { return [] }
        var common = targets(for: first)
        for url in urls.dropFirst() {
            let ops = Set(targets(for: url).map(\.op))
            common = common.filter { ops.contains($0.op) }
        }
        return common
    }
}
