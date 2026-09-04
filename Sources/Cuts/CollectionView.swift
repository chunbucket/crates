import SwiftUI
import UniformTypeIdentifiers

/// The collection: stacked sleeve rows grouped by date.
/// Each row: mini vinyl (art label) · title / cut nº · duration · flac.
/// Rows drag out as real files (Finder, Ableton), reveal on hover buttons,
/// and show live stem-split progress inline.
struct CollectionView: View {
    @ObservedObject var library: Library
    @ObservedObject var downloads: DownloadManager

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            if library.cuts.isEmpty && downloads.current == nil {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        // A finished cut is already in the list below; keep
                        // in-flight and failed cards up top.
                        if let active = downloads.current, active.phase != .done {
                            ActiveRow(cut: active)
                            Divider().opacity(0.25)
                        }
                        ForEach(downloads.queued, id: \.self) { url in
                            QueuedRow(url: url)
                            Divider().opacity(0.25)
                        }
                        ForEach(grouped, id: \.0) { label, cuts in
                            DateHeader(label: label)
                            ForEach(cuts) { cut in
                                CutRow(cut: cut, library: library)
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
    private var grouped: [(String, [Cut])] {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        var out: [(String, [Cut])] = []
        for cut in library.cuts {
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
    @ObservedObject private var stems = StemSplitter.shared
    @State private var hovering = false

    private var isSplitting: Bool { stems.inFlight.contains(cut.filePath) }
    private var splitFailed: Bool { stems.failed.contains(cut.filePath) }

    /// Existing stems, recomputed when a split lands (stemsVersion invalidates).
    private var stemFiles: [URL] {
        _ = stems.stemsVersion
        return StemSplitter.existingStems(forBasename: cut.basename)
    }

    var body: some View {
        let stemsOnDisk = stemFiles
        HStack(spacing: 11) {
            MiniVinyl(artPath: cut.artPath)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(cut.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Text(subLine(stemCount: stemsOnDisk.count))
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(splitFailed && !isSplitting ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)

            if isSplitting {
                ProgressView().controlSize(.small)
            } else if hovering {
                if let first = stemsOnDisk.first {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([first])
                    } label: {
                        Image(systemName: "waveform")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Reveal stems in Finder (\(stemsOnDisk.count)/5)")
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([cut.fileURL])
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Reveal FLAC in Finder")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(hovering ? Color.primary.opacity(0.06) : .clear)
        .onHover { hovering = $0 }
        .onDrag {
            let provider = NSItemProvider(contentsOf: cut.fileURL) ?? NSItemProvider()
            provider.suggestedName = cut.fileURL.lastPathComponent
            return provider
        }
        .contextMenu {
            Button(stemsOnDisk.isEmpty ? "Split to Stems" : "Re-split to Stems") {
                StemSplitter.shared.split(cut)
            }
            .disabled(isSplitting)
            if let first = stemsOnDisk.first {
                Button("Reveal First Stem (\(first.deletingLastPathComponent().lastPathComponent))") {
                    NSWorkspace.shared.activateFileViewerSelecting([first])
                }
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([cut.fileURL])
            }
            Button("Copy YouTube Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(cut.url, forType: .string)
            }
            Divider()
            Button("Remove from Shelf (keeps file)") {
                library.remove(cut)
            }
        }
    }

    private func subLine(stemCount: Int) -> String {
        if let live = stems.status[cut.filePath] {
            return "\(cut.cutLabel) · \(live)"
        }
        var s = "\(cut.cutLabel) · \(cut.durationLabel) · FLAC"
        if stemCount > 0 { s += " · \(stemCount)/5 stems" }
        return s
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
