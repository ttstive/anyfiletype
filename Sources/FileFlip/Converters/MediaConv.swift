import AVFoundation
import ImageIO
import UniformTypeIdentifiers

extension VideoFormat {
    var fileType: AVFileType {
        switch self {
        case .mp4: return .mp4
        case .mov: return .mov
        case .m4v: return .m4v
        }
    }
}

enum MediaConv {
    static func export(_ url: URL, preset: String, type: AVFileType, ext: String) async throws -> URL {
        let asset = AVURLAsset(url: url)
        if preset == AVAssetExportPresetAppleM4A,
           (try? await asset.loadTracks(withMediaType: .audio).isEmpty) ?? false {
            throw ConvertError.failed("\(url.lastPathComponent) has no sound to extract.")
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ConvertError.unreadable(url.lastPathComponent)
        }
        let out = OutputPath.file(for: url, ext: ext)
        session.outputURL = out
        session.outputFileType = type
        session.shouldOptimizeForNetworkUse = true
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { c.resume() }
        }
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: out)
            throw ConvertError.failed(session.error?.localizedDescription ?? "Export failed.")
        }
        return out
    }

    /// Uncompressed audio (WAV, AIFF, CAF), 16-bit, same rate and channels as the source.
    static func pcm(_ url: URL, to f: AudioFormat) throws -> URL {
        let input: AVAudioFile
        do { input = try AVAudioFile(forReading: url) } catch { throw ConvertError.unreadable(url.lastPathComponent) }
        let out = OutputPath.file(for: url, ext: f.rawValue)
        return try OutputPath.producing(out) {
            let format = input.processingFormat
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: f == .aiff,
                AVLinearPCMIsNonInterleaved: false,
            ]
            let output = try AVAudioFile(forWriting: out, settings: settings,
                                         commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_768) else {
                throw ConvertError.failed("Couldn't allocate an audio buffer.")
            }
            while input.framePosition < input.length {
                try input.read(into: buffer)
                if buffer.frameLength == 0 { break }
                try output.write(from: buffer)
            }
            return out
        }
    }

    /// Looping GIF at 10 fps, up to 480 px wide, first 30 seconds.
    static func gif(_ url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw ConvertError.unreadable(url.lastPathComponent) }

        let fps = 10.0
        let frames = min(300, max(1, Int(duration * fps)))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        let tolerance = CMTime(value: 1, timescale: 30)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let out = OutputPath.file(for: url, ext: "gif")
        return try await OutputPath.producing(out) {
            guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.gif.identifier as CFString, frames, nil) else {
                throw ConvertError.failed("Couldn't create the GIF.")
            }
            let fileProps = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]]
            let frameProps = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: 1 / fps]]
            CGImageDestinationSetProperties(dest, fileProps as CFDictionary)
            for i in 0..<frames {
                let time = CMTime(seconds: Double(i) / fps, preferredTimescale: 600)
                let (image, _) = try await generator.image(at: time)
                CGImageDestinationAddImage(dest, image, frameProps as CFDictionary)
            }
            guard CGImageDestinationFinalize(dest) else { throw ConvertError.failed("Couldn't save the GIF.") }
            return out
        }
    }
}

/// Optional engine for formats macOS can't write (WebM, MKV, MP3, FLAC, OGG, WebP).
enum FFmpeg {
    static let path: String? = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    static var isAvailable: Bool { path != nil }

    static func convert(_ url: URL, to ext: String) async throws -> URL {
        guard let exe = path else { throw ConvertError.noFFmpeg }
        let out = OutputPath.file(for: url, ext: ext)
        var args = ["-hide_banner", "-loglevel", "error", "-nostdin", "-i", url.path]
        switch ext {
        case "gif":
            args += ["-vf", "fps=12,scale='min(480,iw)':-2:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse",
                     "-loop", "0", "-t", "30"]
        case "mp3": args += ["-vn", "-q:a", "2"]
        case "m4a": args += ["-vn", "-c:a", "aac", "-b:a", "192k"]
        case "flac", "ogg", "wav": args += ["-vn"]
        case "mp4", "mov": args += ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-movflags", "+faststart"]
        case "webp": args += ["-quality", "90"]
        default: break
        }
        args.append(out.path)
        return try await OutputPath.producing(out) {
            try await Shell.run(exe, args)
            return out
        }
    }
}

enum Archive {
    /// One file or folder becomes "name.zip"; several become "Archive.zip".
    static func zip(_ files: [URL]) async throws -> URL {
        guard let first = files.first else { throw ConvertError.failed("Nothing to compress.") }
        let dir = first.deletingLastPathComponent()
        if files.count == 1 {
            let out = OutputPath.file(for: first, ext: "zip")
            return try await OutputPath.producing(out) {
                try await Shell.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", first.path, out.path])
                return out
            }
        }
        let out = OutputPath.file(for: dir.appendingPathComponent("Archive"), ext: "zip")
        let sameFolder = files.allSatisfy { $0.deletingLastPathComponent().path == dir.path }
        let names = files.map { sameFolder ? $0.lastPathComponent : $0.path }
        return try await OutputPath.producing(out) {
            try await Shell.run("/usr/bin/zip", ["-r", "-q", "-X", out.path] + names, in: dir)
            return out
        }
    }

    static func unzip(_ url: URL) async throws -> URL {
        let folder = OutputPath.folder(in: url.deletingLastPathComponent(),
                                       named: url.deletingPathExtension().lastPathComponent)
        return try await OutputPath.producing(folder) {
            try await Shell.run("/usr/bin/ditto", ["-x", "-k", url.path, folder.path])
            return folder
        }
    }
}
