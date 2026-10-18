# FileFlip

A native macOS menu bar app for converting files. Select files in Finder, press **⌃⌥T** (Control-Option-T), scroll the carousel to a format and press Return. The converted file is saved next to the original. Nothing is uploaded and nothing is overwritten.

Inspired by [Filee](https://github.com/KnifeLemon/Filee), built from scratch in Swift.

## Build and install

Needs macOS 14+ and the Swift toolchain (Xcode Command Line Tools are enough).

```sh
./scripts/build-app.sh --install   # builds, copies to ~/Applications and launches
```

The first time you press ⌃⌥T in Finder, macOS asks whether FileFlip may control Finder. Allow it, because that's how the app reads your selection. If you pressed "Don't Allow", turn it back on in System Settings → Privacy & Security → Automation.

Turn on **Open at Login** from the menu bar icon to keep it running.

## Using it

| Action | Key |
|---|---|
| Open the carousel (Finder in front) | ⌃⌥T |
| Pick files when Finder isn't in front | ⌃⌥T opens a file picker |
| Move | ← → / ↑ ↓ / Tab, trackpad swipe, mouse wheel |
| Jump to a format | type its name (e.g. `pd` for PDF) |
| Convert | Return, Space or click the selected card |
| After converting | Return shows the file in Finder |
| Close | Esc or click elsewhere |

The carousel remembers the last format you picked for each kind of file.

Why ⌃⌥T and not ⌘T: ⌘T opens a new tab in nearly every app, and ⌥⌘T hides the toolbar in Finder.

## Formats

| From | To | Engine |
|---|---|---|
| Images (PNG, JPG, HEIC, TIFF, GIF, BMP, WebP, RAW, SVG…) | PNG, JPG, HEIC, TIFF, GIF, BMP, PDF | ImageIO |
| PDF | PNG or JPG per page, TXT | PDFKit / CoreGraphics |
| DOCX, DOC, RTF, ODT, HTML, TXT, Markdown | PDF, DOCX, RTF, ODT, HTML, TXT, DOC | AppKit text system |
| MOV, MP4, M4V | MP4, MOV, M4V, GIF, M4A (audio) | AVFoundation |
| M4A, MP3, WAV, AIFF, CAF, AAC, FLAC | M4A, WAV, AIFF, CAF | AVFoundation |
| Any file or folder | ZIP | ditto / zip |
| ZIP | Extract | ditto |

With [FFmpeg](https://ffmpeg.org) installed (`brew install ffmpeg`), you also get WebP output, WebM/MKV video, MP3/FLAC/OGG audio, and input from MKV, WebM, AVI, OGG and similar files. Restart FileFlip after installing it.

Selecting several files shows only the formats that all of them support.

## Command line

The same binary converts without UI, which is handy for testing:

```sh
.build/debug/FileFlip targets photo.heic          # list formats
.build/debug/FileFlip convert png photo.heic      # convert
```

## Code map

- `Sources/FileFlip/Formats.swift`: which formats each file can become (the carousel's contents)
- `Sources/FileFlip/Converters/`: one file per engine
- `Sources/FileFlip/App/`: hotkey, Finder selection, carousel panel and view, menu bar

To add a format, add a case to `Op`, list it in `Catalog.targets(for:)` and handle it in `Converter.convert`.

## License

MIT. See [LICENSE](LICENSE).
