import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// A record dragged inside the app: the payload is its id. Finder and
    /// Ableton never see this; they get the file promise next to it.
    static let cratesRecord = UTType(exportedAs: "me.ency.crates.record")
}

extension Color {
    /// The app's accent: the menu bar disc when the crate is open, the scrubber fill.
    static let cratesAmber = Color(red: 1.0, green: 0.71, blue: 0.33)

    /// The Camelot wheel's colours: green at 1 round through cyan, blue,
    /// violet, magenta, red, orange to yellow at 12. A and B share a hue.
    static func camelot(_ camelot: String?) -> Color {
        guard let c = camelot, let n = Int(c.dropLast()), (1...12).contains(n) else { return .secondary }
        let hues: [Double] = [130, 160, 185, 205, 235, 275, 305, 340, 10, 30, 45, 60]
        return Color(hue: hues[n - 1] / 360, saturation: 0.72, brightness: 0.95)
    }
}

/// "8B" in its wheel colour.
struct KeyPill: View {
    let camelot: String?
    let name: String?

    var body: some View {
        let color = Color.camelot(camelot)
        Text(camelot ?? "—")
            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
            .foregroundStyle(camelot == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(color))
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(color.opacity(camelot == nil ? 0.08 : 0.2)))
            .help(name ?? "")
    }
}

/// One record: mini vinyl · title / number · length · BPM · key. Plays and
/// scrubs in place, drags out as a real file (Finder, Ableton), and carries
/// the crate and remove actions in its menu.
struct RecordRow: View {
    let record: Record
    @ObservedObject var library: Library
    /// The list this row is shown in (a crate offers "Remove from This Crate").
    var filter: CrateFilter
    var onRetry: (Record) -> Void
    var onUpdateAndRetry: (Record) -> Void
    var onRemove: (Record) -> Void
    var onNewCrate: (Record?) -> Void
    @ObservedObject private var player = Player.shared
    @State private var hovering = false
    /// Checked once per appearance, not per render.
    @State private var fileMissing = false

    private func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    private func openSource() { if let url = URL(string: record.url) { NSWorkspace.shared.open(url) } }
    /// Failed, or filed but the FLAC has gone: either way the fix is a re-record.
    private var needsRecut: Bool { record.isFailed || fileMissing }
    private var looksLike403: Bool { record.error?.contains("403") == true }
    private var isLoaded: Bool { player.isCurrent(record) }
    private var isPlaying: Bool { isLoaded && player.isPlaying }

    var body: some View {
        let row = HStack(spacing: 11) {
            MiniVinyl(artPath: record.artPath, spinning: isPlaying)
                .frame(width: 44, height: 44)
                .opacity(needsRecut ? 0.55 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                if isLoaded {
                    HStack(spacing: 8) {
                        Scrubber(time: player.time, duration: player.duration) { player.seek(to: $0) }
                        Text("\(Self.mmss(player.time)) / \(Self.mmss(player.duration))")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } else {
                    Text(subLine)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(needsRecut ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)

            // Trailing slot, fixed width: BPM and key columns at rest, the
            // row's controls on hover, the transport while loaded.
            HStack(spacing: 6) {
                if isLoaded {
                    RowButton(symbol: isPlaying ? "pause.fill" : "play.fill",
                              help: isPlaying ? "Pause" : "Play") { player.toggle(record) }
                        .foregroundStyle(Color.cratesAmber)
                } else if hovering {
                    if needsRecut {
                        RowButton(symbol: "arrow.clockwise",
                                  help: record.isFailed ? "Retry this record" : "Record it again (file is missing)") { onRetry(record) }
                            .foregroundStyle(.orange)
                    } else if let url = record.fileURL {
                        RowButton(symbol: "play.fill", help: "Play") { player.play(record) }
                        RowButton(symbol: "magnifyingglass", help: "Reveal FLAC in Finder") { reveal(url) }
                    }
                    RowButton(symbol: "link", help: "Open the original link") { openSource() }
                    RowButton(symbol: "trash", help: "Remove record…") { onRemove(record) }
                } else if !needsRecut {
                    Text(record.bpm.map { String(format: "%.1f", $0) } ?? "—")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(record.bpm == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                    KeyPill(camelot: record.camelot, name: record.key)
                        .frame(width: 34)
                }
            }
            .frame(width: 96, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(hovering ? Color.primary.opacity(0.06) : .clear)
        .onHover { hovering = $0 }
        .onAppear { fileMissing = !record.isFailed && !record.fileExists }
        .contextMenu {
            if needsRecut {
                Button(record.isFailed ? "Retry" : "Record Again") { onRetry(record) }
                if looksLike403 { Button("Update yt-dlp, then Retry") { onUpdateAndRetry(record) } }
            } else if let url = record.fileURL {
                Button("Reveal in Finder") { reveal(url) }
            }
            Divider()
            Menu("Add to Crate") {
                ForEach(library.crates) { crate in
                    let member = crate.recordIDs.contains(record.id)
                    Button {
                        if member { library.remove(record, from: crate.id) } else { library.add(record, to: crate.id) }
                    } label: {
                        if member { Label(crate.name, systemImage: "checkmark") } else { Text(crate.name) }
                    }
                }
                if !library.crates.isEmpty { Divider() }
                Button("New Crate with This…") { onNewCrate(record) }
            }
            if case .crate(let id) = filter {
                Button("Remove from This Crate") { library.remove(record, from: id) }
            }
            Button("Open Link") { openSource() }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.url, forType: .string)
            }
            Divider()
            Button("Remove Record…") { onRemove(record) }
        }

        // Only a record whose file is really there drags out (Finder, Ableton, a crate chip).
        if let url = record.fileURL, !needsRecut {
            row.onDrag {
                let provider = NSItemProvider(contentsOf: url) ?? NSItemProvider()
                provider.suggestedName = url.lastPathComponent
                let id = record.id.uuidString
                provider.registerDataRepresentation(forTypeIdentifier: UTType.cratesRecord.identifier,
                                                    visibility: .ownProcess) { completion in
                    completion(Data(id.utf8), nil)
                    return nil
                }
                return provider
            }
        } else {
            row
        }
    }

    private var subLine: String {
        if record.isFailed { return "\(record.numberLabel) · failed — \(record.error ?? "unknown error")" }
        if fileMissing { return "\(record.numberLabel) · file missing — moved or deleted?" }
        return "\(record.numberLabel) · \(record.durationLabel)"
    }

    static func mmss(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// The 11pt symbol buttons at the trailing edge of a row.
struct RowButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }
}

/// Playback position as a thin track with a knob; drag anywhere on it to seek.
struct Scrubber: View {
    var time: Double
    var duration: Double
    var onSeek: (Double) -> Void
    @State private var dragFraction: Double?

    var body: some View {
        GeometryReader { g in
            let width = g.size.width
            let fraction = dragFraction ?? (duration > 0 ? time / duration : 0)
            let x = max(0, min(width, width * fraction))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.15)).frame(height: 3)
                Capsule().fill(Color.cratesAmber).frame(width: x, height: 3)
                Circle().fill(Color.primary).frame(width: 9, height: 9).offset(x: x - 4.5)
            }
            .frame(height: 14)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { dragFraction = min(max($0.location.x / width, 0), 1) }
                .onEnded {
                    let f = min(max($0.location.x / width, 0), 1)
                    dragFraction = nil
                    onSeek(f * duration)
                })
        }
        .frame(height: 14)
    }
}

struct DateHeader: View {
    let label: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .kerning(1.8)
                .foregroundStyle(.tertiary)
            Rectangle().fill(.tertiary.opacity(0.25)).frame(height: 1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

/// A record in flight, at the top of All.
struct ActiveRow: View {
    @ObservedObject var record: ActiveRecord

    var body: some View {
        HStack(spacing: 11) {
            MiniVinyl(artPath: record.artPath)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Text(statusLine)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            switch record.phase {
            case .cutting(let p):
                Text("\(Int(p * 100))%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(.orange)
            case .done:
                Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(.secondary)
            default:
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var statusLine: String {
        switch record.phase {
        case .fetchingArt: return "\(record.numberLabel) · reading the sleeve…"
        case .cutting: return "\(record.numberLabel) · recording…"
        case .pressing: return "\(record.numberLabel) · pressing to flac…"
        case .done: return "\(record.numberLabel) · filed ✓"
        case .failed(let e): return "failed — \(e)"
        }
    }
}

/// A link waiting its turn behind the current record.
struct QueuedRow: View {
    let url: String

    var body: some View {
        HStack(spacing: 11) {
            MiniVinyl(artPath: nil)
                .frame(width: 44, height: 44)
                .opacity(0.5)
            VStack(alignment: .leading, spacing: 2) {
                Text(YouTubeURL.display(url))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("queued · up next")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

struct MiniVinyl: View {
    var artPath: String?
    var spinning = false
    @State private var angle: Double = 0

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.10))
            Circle()
                .strokeBorder(Color(white: 0.22), lineWidth: 1)
                .padding(2.5)
            artImage
                .clipShape(Circle())
                .padding(9)
            Circle().fill(Color(white: 0.10)).frame(width: 3.5, height: 3.5)
        }
        .rotationEffect(.degrees(angle))
        .onAppear { if spinning { spin() } }
        .onChange(of: spinning) { _, now in
            if now { spin() } else { withAnimation(.easeOut(duration: 0.6)) { angle = angle.truncatingRemainder(dividingBy: 360) } }
        }
    }

    @ViewBuilder
    private var artImage: some View {
        if let p = artPath, let img = NSImage(contentsOfFile: p) {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
        } else {
            Color(white: 0.25)
        }
    }

    private func spin() {
        angle = 0
        withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) { angle = 360 }
    }
}
