import AVFoundation
import Foundation

enum ConvertError: LocalizedError {
    case unreadable(String)
    case failed(String)
    case noFFmpeg

    var errorDescription: String? {
        switch self {
        case .unreadable(let name): return "Couldn't read \(name)."
        case .failed(let why): return why
        case .noFFmpeg: return "This format needs FFmpeg. Install it with: brew install ffmpeg"
        }
    }
}

enum Converter {
    /// Converts every file and returns the files or folders it created.
    static func run(_ op: Op, files: [URL]) async throws -> [URL] {
        if case .zip = op {
            return [try await Archive.zip(files)]
        }
        var outputs: [URL] = []
        for file in files {
            outputs += try await convert(file, op)
        }
        return outputs
    }

    static func convert(_ url: URL, _ op: Op) async throws -> [URL] {
        switch op {
        case .image(let f): return [try ImageConv.convert(url, to: f)]
        case .imageToPDF: return [try ImageConv.toPDF(url)]
        case .resize(let mode): return [try ImageConv.resize(url, mode)]
        case .pdfToImage(let f): return try PDFConv.toImages(url, format: f)
        case .pdfToText: return [try PDFConv.toText(url)]
        case .document(let f): return [try await DocConv.convert(url, to: f)]
        case .documentToPDF: return [try await DocConv.toPDF(url)]
        case .video(let f):
            return [try await MediaConv.export(url, preset: AVAssetExportPresetHighestQuality, type: f.fileType, ext: f.rawValue)]
        case .audioExtract:
            return [try await MediaConv.export(url, preset: AVAssetExportPresetAppleM4A, type: .m4a, ext: "m4a")]
        case .videoToGIF: return [try await MediaConv.gif(url)]
        case .videoResize(let height): return [try await MediaConv.shrink(url, to: height)]
        case .audio(let f):
            if f == .m4a {
                return [try await MediaConv.export(url, preset: AVAssetExportPresetAppleM4A, type: .m4a, ext: "m4a")]
            }
            return [try MediaConv.pcm(url, to: f)]
        case .ffmpeg(let ext): return [try await FFmpeg.convert(url, to: ext)]
        case .zip: return [try await Archive.zip([url])]
        case .unzip: return [try await Archive.unzip(url)]
        }
    }
}

/// Picks output names next to the original. Never overwrites anything.
enum OutputPath {
    static func file(for source: URL, ext: String, suffix: String = "") -> URL {
        let dir = source.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent + suffix
        var candidate = dir.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    static func folder(in dir: URL, named name: String) -> URL {
        var candidate = dir.appendingPathComponent(name, isDirectory: true)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(name) \(n)", isDirectory: true)
            n += 1
        }
        return candidate
    }

    /// Runs `body` and deletes a half-written output if it throws.
    static func producing<T>(_ out: URL, _ body: () throws -> T) throws -> T {
        do { return try body() } catch {
            try? FileManager.default.removeItem(at: out)
            throw error
        }
    }

    static func producing<T>(_ out: URL, _ body: () async throws -> T) async throws -> T {
        do { return try await body() } catch {
            try? FileManager.default.removeItem(at: out)
            throw error
        }
    }
}

enum Shell {
    /// Runs a command and throws with its stderr when it fails.
    static func run(_ exe: String, _ args: [String], in dir: URL? = nil) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: exe)
            proc.arguments = args
            if let dir { proc.currentDirectoryURL = dir }
            let err = Pipe()
            proc.standardError = err
            proc.standardOutput = FileHandle.nullDevice
            proc.standardInput = FileHandle.nullDevice
            proc.terminationHandler = { p in
                let data = err.fileHandleForReading.readDataToEndOfFile()
                if p.terminationStatus == 0 {
                    c.resume()
                } else {
                    let msg = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    let name = URL(fileURLWithPath: exe).lastPathComponent
                    c.resume(throwing: ConvertError.failed(msg.isEmpty ? "\(name) failed." : String(msg.suffix(300))))
                }
            }
            do { try proc.run() } catch { c.resume(throwing: error) }
        }
    }
}
