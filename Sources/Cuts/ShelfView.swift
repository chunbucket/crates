import SwiftUI
import UniformTypeIdentifiers

/// Content of the slide-in shelf panel: a drop target that becomes the
/// record player while a cut is in progress. Drops are accepted by the
/// AppKit DropCatcherView underneath; this view only renders.
struct ShelfSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

struct ShelfView: View {
    @ObservedObject var downloads: DownloadManager
    @ObservedObject var state: ShelfState
    var onClose: () -> Void
    var onSize: (CGSize) -> Void

    @State private var closeHover = false

    private var dropHover: Bool { state.hovering }

    var body: some View {
        Group {
            if let cut = downloads.current {
                PlayerCard(cut: cut, queuedCount: downloads.queued.count)
            } else {
                dropTarget
            }
        }
        .frame(width: 236)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(dropHover ? 0.35 : 0.12), lineWidth: 1)
                )
        )
        .overlay(alignment: .topLeading) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(closeHover ? 0.95 : 0.45))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.black.opacity(closeHover ? 0.6 : 0.35)))
            }
            .buttonStyle(.plain)
            .onHover { closeHover = $0 }
            .padding(8)
            .help("Put the shelf away (download keeps running)")
        }
        // Report the real laid-out size so the panel can track it exactly —
        // no stale fittingSize, no guessed re-measure delays.
        .background(
            GeometryReader { g in
                Color.clear.preference(key: ShelfSizeKey.self, value: g.size)
            }
        )
        .onPreferenceChange(ShelfSizeKey.self) { onSize($0) }
        .environment(\.colorScheme, .dark)
    }

    private var dropTarget: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                    .foregroundStyle(Color.white.opacity(dropHover ? 0.8 : 0.35))
                Image(systemName: "arrow.down")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(dropHover ? 0.9 : 0.4))
            }
            .frame(width: 120, height: 120)
            .scaleEffect(dropHover ? 1.06 : 1.0)
            .animation(.spring(duration: 0.25), value: dropHover)

            Text(state.notice ?? "drop to cut")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
    }
}

/// The record player while cutting: vinyl + corner mark + title + status.
struct PlayerCard: View {
    @ObservedObject var cut: ActiveCut
    var queuedCount: Int = 0

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(cut.cutLabel)
                    Text(cut.dateLabel)
                }
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .kerning(1.2)
                .foregroundStyle(.white.opacity(0.55))
            }

            VinylView(artPath: cut.artPath,
                      progress: progressValue,
                      spinning: isSpinning)
                .frame(width: 176, height: 176)
                .shadow(color: .black.opacity(0.5), radius: 12, y: 6)

            VStack(spacing: 3) {
                Text(cut.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(statusLine)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(cut.phase.isFailed ? .orange.opacity(0.9) : .white.opacity(0.5))
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                if queuedCount > 0 {
                    Text("+\(queuedCount) queued")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
    }

    private var progressValue: Double? {
        switch cut.phase {
        case .fetchingArt: return 0
        case .cutting(let p): return p
        case .pressing, .done: return 1
        case .failed: return nil
        }
    }

    private var isSpinning: Bool { !cut.phase.isTerminal }

    private var statusLine: String {
        switch cut.phase {
        case .fetchingArt: return "reading the sleeve…"
        case .cutting(let p): return String(format: "cutting… %d%%", Int(p * 100))
        case .pressing: return "pressing to flac…"
        case .done: return "filed ✓"
        case .failed(let why): return "cut failed — \(why)"
        }
    }
}
