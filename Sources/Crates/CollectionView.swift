import SwiftUI
import UniformTypeIdentifiers

/// The collection: stacked sleeve rows grouped by date.
/// Each row: mini vinyl (art label) · title / record nº · duration · flac.
/// Rows drag out as real files (Finder, Ableton) and reveal on hover; a
/// failed row shows its reason and a Retry.
struct CollectionView: View {
    @ObservedObject var library: Library
    @ObservedObject var downloads: DownloadManager
    var onRetry: (Record) -> Void
    /// For a 403: refresh yt-dlp first, then re-record.
    var onUpdateAndRetry: (Record) -> Void
    /// Remove from the shelf (owner decides about the file).
    var onRemove: (Record) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            if library.records.isEmpty && downloads.current == nil {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        // In flight up top; once it lands (filed or failed)
                        // the library row below takes over.
                        if let active = downloads.inFlight {
                            ActiveRow(record: active)
                            Divider().opacity(0.25)
                        }
                        ForEach(downloads.queued) { item in
                            QueuedRow(url: item.url)
                            Divider().opacity(0.25)
                        }
                        ForEach(grouped, id: \.0) { label, records in
                            DateHeader(label: label)
                            ForEach(records) { record in
                                RecordRow(record: record, onRetry: onRetry, onUpdateAndRetry: onUpdateAndRetry, onRemove: onRemove)
                                Divider().opacity(0.25)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 340, height: 440)
    }

    /// Records grouped by calendar day, newest first (library is already sorted).
    /// A row being retried is represented by the ActiveRow while in flight.
    private var grouped: [(String, [Record])] {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        let inFlight = downloads.inFlight?.id
        var out: [(String, [Record])] = []
        for record in library.records where record.id != inFlight {
            let label = cal.isDateInToday(record.date) ? "TODAY"
                : cal.isDateInYesterday(record.date) ? "YESTERDAY"
                : fmt.string(from: record.date).uppercased()
            if out.last?.0 == label {
                out[out.count - 1].1.append(record)
            } else {
                out.append((label, [record]))
            }
        }
        return out
    }

    private var header: some View {
        HStack {
            Text("CRATE")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .kerning(2.5)
            Spacer()
            Text("\(library.records.count) in the crate")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "record.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Nothing in the crate yet")
                .font(.system(size: 13, weight: .semibold))
            Text("Drag a link onto the menu bar icon —\nthe record player will catch it.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
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

struct RecordRow: View {
    let record: Record
    var onRetry: (Record) -> Void
    var onUpdateAndRetry: (Record) -> Void
    var onRemove: (Record) -> Void
    @ObservedObject private var player = Player.shared
    @State private var hovering = false
    /// Checked once per appearance, not per render.
    @State private var fileMissing = false

    private func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    /// Failed, or filed but the FLAC has gone: either way the fix is a re-record.
    private var needsRecut: Bool { record.isFailed || fileMissing }
    private var looksLike403: Bool { record.error?.contains("403") == true }
    /// This row is loaded in the player (playing or paused).
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

            if isLoaded {
                // Transport stays visible while loaded, not just on hover.
                RowButton(symbol: isPlaying ? "pause.fill" : "play.fill",
                          help: isPlaying ? "Pause" : "Play") { player.toggle(record) }
                    .foregroundStyle(Color.cutsAmber)
            } else if hovering {
                if needsRecut {
                    Button { onRetry(record) } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                    .help(record.isFailed ? "Retry this record" : "Record it again (file is missing)")
                } else if let url = record.fileURL {
                    RowButton(symbol: "play.fill", help: "Play") { player.play(record) }
                    RowButton(symbol: "magnifyingglass", help: "Reveal FLAC in Finder") { reveal(url) }
                }
                RowButton(symbol: "trash", help: "Remove record…") { onRemove(record) }
            }
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
            Button("Copy YouTube Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.url, forType: .string)
            }
            Divider()
            Button("Remove Record…") { onRemove(record) }
        }

        // Only a record whose file is really there drags out (Finder, Ableton).
        if let url = record.fileURL, !needsRecut {
            row.onDrag {
                let provider = NSItemProvider(contentsOf: url) ?? NSItemProvider()
                provider.suggestedName = url.lastPathComponent
                return provider
            }
        } else {
            row
        }
    }

    private var subLine: String {
        if record.isFailed { return "\(record.numberLabel) · failed — \(record.error ?? "unknown error")" }
        if fileMissing { return "\(record.numberLabel) · file missing — moved or deleted?" }
        return "\(record.numberLabel) · \(record.durationLabel) · FLAC"
    }

    private static func mmss(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

extension Color {
    /// The app's accent: the menu bar disc when the collection is open, the scrubber fill.
    static let cutsAmber = Color(red: 1.0, green: 0.71, blue: 0.33)
}

/// The 11pt symbol buttons that appear at the trailing edge of a row.
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
                Capsule().fill(Color.cutsAmber).frame(width: x, height: 3)
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
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
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

    private func spin() {
        angle = 0
        withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) { angle = 360 }
    }

    @ViewBuilder
    private var artImage: some View {
        if let p = artPath, let img = NSImage(contentsOfFile: p) {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
        } else {
            Color(white: 0.25)
        }
    }
}
