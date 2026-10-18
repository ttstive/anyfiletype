# FileFlip

A native macOS menu bar app for converting files. Select files in Finder, press **⌃⌥T** (Control-Option-T), scroll the carousel to a format and press Return. The converted file is saved next to the original. Nothing is uploaded and nothing is overwritten.

Inspired by [Filee](https://github.com/KnifeLemon/Filee), built from scratch in Swift.

## Build and install

Needs macOS 14+ and the Swift toolchain (Xcode Command Line Tools are enough).

```sh
./scripts/build-app.sh --install   # builds, copies to /Applications and launches
```

The first time you press ⌃⌥T in Finder, macOS asks whether FileFlip may control Finder. Allow it, because that's how the app reads your selection. If you pressed "Don't Allow", turn it back on in System Settings → Privacy & Security → Automation.

Turn on **Open at Login** from the menu bar icon to keep it running.

## Using it

Three ways to open it:

- **Shortcut:** select files in Finder and press ⌃⌥T.
- **Click the app** in Spotlight, Launchpad or the Dock: a file picker opens.
- **Drag files onto the app icon** (keep it in the Dock for this): the carousel opens with those files.

| Action | Key |
|---|---|
| Open the carousel (Finder in front) | ⌃⌥T |
| Pick files when Finder isn't in front | ⌃⌥T opens a file picker |
| Move | ← → / ↑ ↓ / Tab, trackpad swipe, mouse wheel |
| Jump to a format | type its name (e.g. `pd` for PDF) |
| Convert | Return, Space or click the selected card |
| After converting | The panel stays open with the file name and folder. Return or **Show in Finder** reveals it |
| Close | Esc or **Close**. Clicking elsewhere closes it only while you're still picking a format |

The carousel remembers the last format you picked for each kind of file. Your last 10 converted files are listed under **Recent Conversions** in the menu bar icon; pick one to show it in Finder.

Why ⌃⌥T and not ⌘T: ⌘T opens a new tab in nearly every app, and ⌥⌘T hides the toolbar in Finder.

## Formats

| From | To | Engine |
|---|---|---|
| Images (PNG, JPG, HEIC, TIFF, GIF, BMP, WebP, RAW, SVG…) | PNG, JPG, HEIC, TIFF, GIF, BMP, PDF | ImageIO |
| PDF | PNG or JPG per page, TXT | PDFKit / CoreGraphics |
| DOCX, DOC, RTF, ODT, HTML, TXT, Markdown | PDF, DOCX, RTF, ODT, HTML, TXT, DOC | AppKit text system |
| MOV, MP4, M4V | MP4, MOV, M4V, GIF, M4A (audio) | AVFoundation |
| M4A, MP3, WAV, AIFF, CAF, AAC, FLAC | M4A, WAV, AIFF, CAF | AVFoundation |
| Images | Square 512 (profile picture), Square 1080, 1920 px, 50%, Under 1 MB | CoreGraphics |
| MOV, MP4, M4V | 720p, 540p (smaller video) | AVFoundation |
| Any file or folder | ZIP | ditto / zip |
| ZIP | Extract | ditto |

With [FFmpeg](https://ffmpeg.org) installed (`brew install ffmpeg`), you also get WebP output, WebM/MKV video, MP3/FLAC/OGG audio, and input from MKV, WebM, AVI, OGG and similar files. Restart FileFlip after installing it.

Selecting several files shows only the formats that all of them support.

### Resizing

Resized copies are saved next to the original with the size in the name, e.g. `photo 512x512.jpg`.

- **Square 512 / Square 1080** crop the center of the photo to a square, which works for profile pictures in most apps.
- **1920 px** limits the longest side, and **50%** halves both sides.
- **Under 1 MB** lowers JPEG quality, then size, until the file fits upload limits.
- PNGs stay PNG so transparency is kept (except Under 1 MB, which is always JPG). Other images become JPG, which every app accepts.
- Images are never enlarged. Videos already at or below 720p/540p are left alone with a message.

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
<img width="371" height="138" alt="Captura de Tela 2026-10-18 às 14 52 02" src="https://github.com/user-attachments/assets/67df87cf-d7e4-44e0-aa34-b1e540eea5ba" />
<img width="570" height="217" alt="image" src="https://github.com/user-attachments/assets/0479e016-476c-45d6-a010-b87c646b9391" />


## License

MIT. See [LICENSE](LICENSE).
