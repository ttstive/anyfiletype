import AppKit
import SwiftUI

struct CarouselView: View {
    @ObservedObject var model: CarouselModel

    var body: some View {
        VStack(spacing: 18) {
            header
            switch model.state {
            case .done(let outputs):
                ResultView(outputs: outputs, model: model)
            case .failed(let message):
                FailureView(message: message, model: model)
            case .choosing, .working:
                if model.targets.isEmpty {
                    Text("No conversions for this selection")
                        .foregroundStyle(.secondary)
                        .frame(height: 150)
                } else {
                    carousel
                }
            }
            footer
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 24)
        .frame(width: 600)
        .background(
            VisualEffect()
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        )
        .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
        .padding(30)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let first = model.files.first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: first.path))
                    .resizable()
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.files.count == 1 ? first.lastPathComponent
                         : "\(first.lastPathComponent) + \(model.files.count - 1) more")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("Convert to…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !model.targets.isEmpty {
                Text("\(model.index + 1) / \(model.targets.count)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var carousel: some View {
        ZStack {
            ForEach(Array(model.targets.enumerated()), id: \.element.id) { i, target in
                let distance = CGFloat(i - model.index)
                let far = min(abs(distance), 3)
                FormatCard(target: target, selected: distance == 0)
                    .scaleEffect(1 - far * 0.13)
                    .offset(x: distance * 116)
                    .opacity(abs(distance) > 3 ? 0 : 1 - far * 0.25)
                    .zIndex(-abs(distance))
                    .onTapGesture { model.select(i) }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .mask(
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.12),
                .init(color: .black, location: 0.88),
                .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
        )
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: model.index)
        .saturation(model.state == .choosing ? 1 : 0.4)
    }

    @ViewBuilder
    private var footer: some View {
        Group {
            switch model.state {
            case .choosing:
                Text("← →  or scroll   ·   ↩  convert   ·   esc  close")
                    .foregroundStyle(.secondary)
            case .working(let title):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Converting to \(title)…")
                }
            case .done:
                Text("↩  show in Finder   ·   esc  close")
                    .foregroundStyle(.secondary)
            case .failed:
                Text("esc  close")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .frame(height: 34)
    }
}

/// After converting: what was saved, where, and what to do next.
struct ResultView: View {
    let outputs: [URL]
    @ObservedObject var model: CarouselModel

    private var folder: URL { outputs[0].deletingLastPathComponent() }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text(outputs.count == 1 ? "Saved \(outputs[0].lastPathComponent)" : "Saved \(outputs.count) files")
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if outputs.count > 1 {
                        Text(outputs.prefix(3).map(\.lastPathComponent).joined(separator: ", ")
                             + (outputs.count > 3 ? " + \(outputs.count - 3) more" : ""))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: folder.path))
                    .resizable()
                    .frame(width: 18, height: 18)
                Text((folder.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
            .help(folder.path)

            HStack {
                Spacer()
                Button("Close") { model.close() }
                    .controlSize(.large)
                Button("Show in Finder") { model.revealOutputs() }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(height: 150)
    }
}

struct FailureView: View {
    let message: String
    @ObservedObject var model: CarouselModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Couldn't convert")
                        .font(.system(size: 15, weight: .semibold))
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Close") { model.close() }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(height: 150)
    }
}

struct FormatCard: View {
    let target: Target
    let selected: Bool

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: target.symbol)
                .font(.system(size: 24, weight: .medium))
            Text(target.title)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(target.caption)
                .font(.system(size: 10.5))
                .opacity(0.75)
                .lineLimit(1)
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .frame(width: 118, height: 134)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(selected ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.primary.opacity(0.07)))
        )
        .shadow(color: selected ? Color.accentColor.opacity(0.4) : .clear, radius: 12, y: 6)
        .contentShape(Rectangle())
    }
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
