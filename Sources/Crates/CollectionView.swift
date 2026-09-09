import SwiftUI
import UniformTypeIdentifiers

/// The crate browser: the crate list at the root, a record list inside one.
struct CollectionView: View {
    @ObservedObject var library: Library
    @ObservedObject var downloads: DownloadManager
    @ObservedObject var nav: CrateNavigation
    var onRetry: (Record) -> Void
    var onUpdateAndRetry: (Record) -> Void
    var onRemove: (Record) -> Void
    var onNewCrate: (Record?) -> Void
    var onRenameCrate: (Crate) -> Void

    /// Push (a crate opens) slides the list in from the right and the grid
    /// out to the left; pop reverses both.
    private func go(_ filter: CrateFilter?) {
        withAnimation(.easeInOut(duration: 0.28)) { nav.filter = filter }
    }

    var body: some View {
        ZStack {
            if let filter = nav.filter {
                RecordListView(filter: filter, library: library, downloads: downloads,
                               onBack: { go(nil) }, onOpen: { go($0) },
                               onRetry: onRetry, onUpdateAndRetry: onUpdateAndRetry,
                               onRemove: onRemove, onNewCrate: onNewCrate)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            } else {
                CrateListView(library: library, onOpen: { go($0) },
                              onNew: { onNewCrate(nil) }, onRename: onRenameCrate)
                    .transition(.move(edge: .leading))
            }
        }
        .frame(width: 340, height: 440)
        .clipped()
    }
}

/// Where the panel is: nil = the crate list. Owned by the panel so deep links
/// (crates://crate?name=…) can steer it.
final class CrateNavigation: ObservableObject {
    @Published var filter: CrateFilter?
}

/// Inside a crate: back, a strip of every crate (drop targets), the filter
/// and sort, then the rows.
struct RecordListView: View {
    let filter: CrateFilter
    @ObservedObject var library: Library
    @ObservedObject var downloads: DownloadManager
    var onBack: () -> Void
    var onOpen: (CrateFilter) -> Void
    var onRetry: (Record) -> Void
    var onUpdateAndRetry: (Record) -> Void
    var onRemove: (Record) -> Void
    var onNewCrate: (Record?) -> Void

    @AppStorage("recordSort") private var sort = "date"          // date | bpm | key
    @AppStorage("recordSubfilter") private var subfilter = "all" // all | sorted | unsorted (All crate only)

    private var title: String {
        switch filter {
        case .all: return "All"
        case .unsorted: return "Unsorted"
        case .crate(let id): return library.crate(id)?.name ?? "Crate"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            if !library.crates.isEmpty {
                CrateStrip(library: library, current: filter, onOpen: onOpen)
            }
            toolbar
            Divider().opacity(0.25)
            if records.isEmpty && !(filter == .all && downloads.current != nil) {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if filter == .all {
                            if let active = downloads.inFlight {
                                ActiveRow(record: active)
                                Divider().opacity(0.25)
                            }
                            ForEach(downloads.queued) { item in
                                QueuedRow(url: item.url)
                                Divider().opacity(0.25)
                            }
                        }
                        if sort == "date" {
                            ForEach(grouped, id: \.0) { label, group in
                                DateHeader(label: label)
                                ForEach(group) { row($0) }
                            }
                        } else {
                            ForEach(records) { row($0) }
                        }
                    }
                }
            }
        }
    }

    private func row(_ record: Record) -> some View {
        VStack(spacing: 0) {
            RecordRow(record: record, library: library, filter: filter,
                      onRetry: onRetry, onUpdateAndRetry: onUpdateAndRetry,
                      onRemove: onRemove, onNewCrate: onNewCrate)
            Divider().opacity(0.25)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // A labelled way back, clearly a control and not part of the title.
                Button(action: onBack) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold))
                        Text("Crates").font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
                Text("\(records.count) \(records.count == 1 ? "record" : "records")")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(title.uppercased())
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .kerning(2.5)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            if filter == .all {
                ForEach([("all", "All"), ("sorted", "Sorted"), ("unsorted", "Unsorted")], id: \.0) { value, label in
                    Button(label) { subfilter = value }
                        .buttonStyle(.plain)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .kerning(1.2)
                        .foregroundStyle(subfilter == value ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                }
            }
            Spacer()
            Menu {
                ForEach([("date", "Date"), ("bpm", "BPM"), ("key", "Key")], id: \.0) { value, label in
                    Button { sort = value } label: {
                        if sort == value { Label(label, systemImage: "checkmark") } else { Text(label) }
                    }
                }
            } label: {
                Text("\(sort == "bpm" ? "BPM" : sort == "key" ? "KEY" : "DATE") ▾")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .kerning(1.2)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: filter == .all ? "record.circle" : "shippingbox")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(filter == .all ? "Nothing in the crate yet" : "Nothing in this crate yet")
                .font(.system(size: 13, weight: .semibold))
            Text(filter == .all
                 ? "Drag a link onto the menu bar icon —\nthe record player will catch it."
                 : "Drag a record onto this crate's chip,\nor use Add to Crate in a record's menu.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Which records, in what order

    private var records: [Record] {
        var list = library.records(in: filter)
        if filter == .all {
            if subfilter == "sorted" { list = list.filter { library.isSorted($0) } }
            if subfilter == "unsorted" { list = list.filter { !library.isSorted($0) } }
        }
        // A record being re-recorded is represented by the ActiveRow while in flight.
        if let inFlight = downloads.inFlight?.id { list.removeAll { $0.id == inFlight } }
        switch sort {
        case "bpm": return list.sorted { ($0.bpm ?? .infinity, $0.number) < ($1.bpm ?? .infinity, $1.number) }
        case "key": return list.sorted { (Self.wheel($0.camelot), $0.number) < (Self.wheel($1.camelot), $1.number) }
        default: return list   // library order: newest first
        }
    }

    /// Camelot wheel order: 1A, 1B, 2A, 2B … 12B; unknown last.
    static func wheel(_ camelot: String?) -> Int {
        guard let c = camelot, let n = Int(c.dropLast()), let letter = c.last else { return 999 }
        return n * 2 + (letter == "B" ? 1 : 0)
    }

    /// Records grouped by calendar day, newest first.
    private var grouped: [(String, [Record])] {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        var out: [(String, [Record])] = []
        for record in records {
            let label = cal.isDateInToday(record.date) ? "TODAY"
                : cal.isDateInYesterday(record.date) ? "YESTERDAY"
                : fmt.string(from: record.date).uppercased()
            if out.last?.0 == label { out[out.count - 1].1.append(record) } else { out.append((label, [record])) }
        }
        return out
    }
}

/// Every crate as a chip. Tap to go there; drop a record on it to file it.
struct CrateStrip: View {
    @ObservedObject var library: Library
    var current: CrateFilter
    var onOpen: (CrateFilter) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(library.crates) { crate in
                    CrateChip(name: crate.name, isCurrent: current == .crate(crate.id),
                              onTap: { onOpen(.crate(crate.id)) },
                              onDropRecord: { library.add($0, to: crate.id) },
                              resolve: { url in library.records.first { $0.filePath == url.path } })
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }
}

struct CrateChip: View {
    let name: String
    let isCurrent: Bool
    let onTap: () -> Void
    let onDropRecord: (Record) -> Void
    let resolve: (URL) -> Record?
    @State private var targeted = false

    var body: some View {
        Button(action: onTap) {
            Text(name)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .kerning(0.8)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(targeted ? Color.cratesAmber.opacity(0.35)
                                           : isCurrent ? Color.primary.opacity(0.18) : Color.primary.opacity(0.06)))
                .overlay(Capsule().strokeBorder(targeted ? Color.cratesAmber : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isCurrent || targeted ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    if let record = resolve(url) {
                        onDropRecord(record)
                        Log.d("dropped \(record.numberLabel) onto crate \(name)")
                    }
                }
            }
            return true
        }
    }
}
