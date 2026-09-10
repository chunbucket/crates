import SwiftUI
import UniformTypeIdentifiers

/// The root of the panel: every crate as an icon in a three-across grid —
/// All and Unsorted first, then the user's crates, newest first.
struct CrateListView: View {
    @ObservedObject var library: Library
    @ObservedObject var downloads: DownloadManager
    var onOpen: (CrateFilter) -> Void
    var onNew: () -> Void
    var onRename: (Crate) -> Void
    var onRetry: (Record) -> Void
    var onUpdateAndRetry: (Record) -> Void
    var onRemove: (Record) -> Void
    var onNewCrate: (Record?) -> Void

    /// What's fresh: today's records, newest first, minus the one in flight.
    private var fresh: [Record] {
        let inFlight = downloads.inFlight?.id
        return Array(library.records.filter { Calendar.current.isDateInToday($0.date) && $0.id != inFlight }.prefix(5))
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    /// A dragged row carries its FLAC's URL; find the record by path.
    private func resolve(_ url: URL) -> Record? { library.records.first { $0.filePath == url.path } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("CRATES")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .kerning(2.5)
                Spacer()
                Button(action: onNew) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("New crate")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider().opacity(0.4)

            ScrollView {
                // Newly recorded, above the crates: in flight, queued, then today's.
                if downloads.inFlight != nil || !downloads.queued.isEmpty || !fresh.isEmpty {
                    LazyVStack(spacing: 0) {
                        DateHeader(label: "NEW")
                        if let active = downloads.inFlight {
                            ActiveRow(record: active)
                            Divider().opacity(0.25)
                        }
                        ForEach(downloads.queued) { item in
                            QueuedRow(url: item.url)
                            Divider().opacity(0.25)
                        }
                        ForEach(fresh) { record in
                            RecordRow(record: record, library: library, filter: .all,
                                      onRetry: onRetry, onUpdateAndRetry: onUpdateAndRetry,
                                      onRemove: onRemove, onNewCrate: onNewCrate)
                            Divider().opacity(0.25)
                        }
                    }
                    .padding(.bottom, 6)
                }
                LazyVGrid(columns: columns, spacing: 16) {
                    CrateTile(name: "All", count: library.records.count,
                              sleeves: Array(library.records.prefix(3)), onOpen: { onOpen(.all) })
                    CrateTile(name: "Unsorted", count: library.count(in: .unsorted),
                              sleeves: Array(library.records(in: .unsorted).prefix(3)), onOpen: { onOpen(.unsorted) },
                              onDrop: { record in   // dropping here takes it out of every crate
                                  for crate in library.crates(containing: record) { library.remove(record, from: crate.id) }
                              }, resolve: resolve)
                    ForEach(library.crates) { crate in
                        CrateTile(name: crate.name, count: crate.recordIDs.count,
                                  sleeves: Array(library.records(in: .crate(crate.id)).prefix(3)),
                                  onOpen: { onOpen(.crate(crate.id)) },
                                  onDrop: { library.add($0, to: crate.id) }, resolve: resolve)
                            .contextMenu {
                                Button("Rename…") { onRename(crate) }
                                Divider()
                                Button("Delete Crate (records stay)") { library.deleteCrate(crate.id) }
                            }
                    }
                }
                .padding(14)
            }
        }
    }
}

/// A crate icon with its name and count under it. A record row dragged onto
/// it is filed there.
struct CrateTile: View {
    let name: String
    let count: Int
    let sleeves: [Record]
    var onOpen: () -> Void
    var onDrop: ((Record) -> Void)? = nil
    var resolve: ((URL) -> Record?)? = nil
    @State private var hovering = false
    @State private var targeted = false

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 7) {
                MilkCrateIcon(sleeves: sleeves, size: 84)
                    .scaleEffect(hovering || targeted ? 1.06 : 1)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.cratesAmber, lineWidth: targeted ? 2 : 0)
                        .padding(-6))
                    .animation(.spring(duration: 0.25), value: hovering || targeted)
                Text(name)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                Text("\(count) \(count == 1 ? "record" : "records")")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.07 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .onDrop(of: [.fileURL], isTargeted: onDrop == nil ? .constant(false) : $targeted) { providers in
            guard let onDrop, let resolve, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                guard let url = object as? URL ?? (object as? NSURL).map({ $0 as URL }) else { return }
                DispatchQueue.main.async {
                    if let record = resolve(url) {
                        onDrop(record)
                        Log.d("dropped \(record.numberLabel) onto crate \(name)")
                    }
                }
            }
            return true
        }
    }
}
