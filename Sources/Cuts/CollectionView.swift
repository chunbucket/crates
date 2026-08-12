import SwiftUI
import UniformTypeIdentifiers

/// Menu bar popover: the collection as stacked sleeve rows.
/// Each row: mini vinyl (art label) · title / cut nº · duration · flac.
/// Rows drag out as real files (Finder, Ableton) and reveal on double-click.
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
                    LazyVStack(spacing: 0) {
                        if let active = downloads.current {
                            ActiveRow(cut: active)
                            Divider().opacity(0.25)
                        }
                        ForEach(library.cuts) { cut in
                            CutRow(cut: cut, library: library)
                            Divider().opacity(0.25)
                        }
                    }
                }
            }
        }
        .frame(width: 340, height: 440)
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
            Text("Drag a YouTube link out of Safari —\nthe record player will catch it.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct CutRow: View {
    let cut: Cut
    let library: Library
    @ObservedObject private var stems = StemSplitter.shared
    @State private var hovering = false

    private var isSplitting: Bool { stems.inFlight.contains(cut.filePath) }

    var body: some View {
        HStack(spacing: 11) {
            MiniVinyl(artPath: cut.artPath)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(cut.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Text(isSplitting
                     ? "\(cut.cutLabel) · splitting stems…"
                     : "\(cut.cutLabel) · \(cut.durationLabel) · FLAC")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if isSplitting {
                ProgressView().controlSize(.small)
            } else if hovering {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([cut.fileURL])
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Reveal in Finder")
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
            Button("Split to Stems") {
                StemSplitter.shared.split(cut)
            }
            .disabled(isSplitting)
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
            if case .cutting(let p) = cut.phase {
                Text("\(Int(p * 100))%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
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
