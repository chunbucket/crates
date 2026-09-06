import SwiftUI
import UniformTypeIdentifiers

/// The collection: stacked sleeve rows grouped by date.
/// Each row: mini vinyl (art label) · title / cut nº · duration · flac.
/// Rows drag out as real files (Finder, Ableton) and reveal on hover; a
/// failed row shows its reason and a Retry.
struct CollectionView: View {
    @ObservedObject var library: Library
    @ObservedObject var downloads: DownloadManager
    var onRetry: (Cut) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            if library.cuts.isEmpty && downloads.current == nil {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        // In flight up top; once it lands (filed or failed)
                        // the library row below takes over.
                        if let active = downloads.inFlight {
                            ActiveRow(cut: active)
                            Divider().opacity(0.25)
                        }
                        ForEach(downloads.queued) { item in
                            QueuedRow(url: item.url)
                            Divider().opacity(0.25)
                        }
                        ForEach(grouped, id: \.0) { label, cuts in
                            DateHeader(label: label)
                            ForEach(cuts) { cut in
                                CutRow(cut: cut, library: library, onRetry: onRetry)
                                Divider().opacity(0.25)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 340, height: 440)
    }

    /// Cuts grouped by calendar day, newest first (library is already sorted).
    /// A row being retried is represented by the ActiveRow while in flight.
    private var grouped: [(String, [Cut])] {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        let inFlight = downloads.inFlight?.id
        var out: [(String, [Cut])] = []
        for cut in library.cuts where cut.id != inFlight {
            let label = cal.isDateInToday(cut.date) ? "TODAY"
                : cal.isDateInYesterday(cut.date) ? "YESTERDAY"
                : fmt.string(from: cut.date).uppercased()
            if out.last?.0 == label {
                out[out.count - 1].1.append(cut)
            } else {
                out.append((label, [cut]))
            }
        }
        return out
    }

    private var header: some View {
        HStack {
            Text("CUTS")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .kerning(2.5)
            Spacer()
            Text("\(library.cuts.count) on the shelf")
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
            Text("Nothing on the shelf yet")
                .font(.system(size: 13, weight: .semibold))
            Text("Drag a YouTube link onto the menu bar icon —\nthe record player will catch it.")
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

struct CutRow: View {
    let cut: Cut
    let library: Library
    var onRetry: (Cut) -> Void
    @State private var hovering = false

    private func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    var body: some View {
        let row = HStack(spacing: 11) {
            MiniVinyl(artPath: cut.artPath)
                .frame(width: 44, height: 44)
                .opacity(cut.isFailed ? 0.55 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(cut.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Text(subLine)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(cut.isFailed ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)

            if hovering {
                if cut.isFailed {
                    Button { onRetry(cut) } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                    .help("Retry this cut")
                } else if let url = cut.fileURL {
                    Button { reveal(url) } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Reveal FLAC in Finder")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(hovering ? Color.primary.opacity(0.06) : .clear)
        .onHover { hovering = $0 }
        .contextMenu {
            if cut.isFailed {
                Button("Retry") { onRetry(cut) }
            } else if let url = cut.fileURL {
                Button("Reveal in Finder") { reveal(url) }
            }
            Button("Copy YouTube Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(cut.url, forType: .string)
            }
            Divider()
            Button(cut.isFailed ? "Remove from Shelf" : "Remove from Shelf (keeps file)") {
                library.remove(cut)
            }
        }

        // Only a filed cut drags out as a file (Finder, Ableton).
        if let url = cut.fileURL, !cut.isFailed {
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
        if cut.isFailed { return "\(cut.cutLabel) · failed — \(cut.error ?? "unknown error")" }
        return "\(cut.cutLabel) · \(cut.durationLabel) · FLAC"
    }
}

struct ActiveRow: View {
    @ObservedObject var cut: ActiveCut

    var body: some View {
        HStack(spacing: 11) {
            MiniVinyl(artPath: cut.artPath)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(cut.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Text(statusLine)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            switch cut.phase {
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
        switch cut.phase {
        case .fetchingArt: return "\(cut.cutLabel) · reading the sleeve…"
        case .cutting: return "\(cut.cutLabel) · cutting…"
        case .pressing: return "\(cut.cutLabel) · pressing to flac…"
        case .done: return "\(cut.cutLabel) · filed ✓"
        case .failed(let e): return "failed — \(e)"
        }
    }
}

/// A link waiting its turn behind the current cut.
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
