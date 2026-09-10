import SwiftUI
import UniformTypeIdentifiers

/// The crate browser: the crate list at the root, a record list inside one.
struct CollectionView: View {
    @ObservedObject var library: Library
    @ObservedObject var downloads: DownloadManager
    @ObservedObject var nav: CrateNavigation
    @ObservedObject var prompt: PromptState
    var onRetry: (Record) -> Void
    var onUpdateAndRetry: (Record) -> Void
    var onRemove: (Record) -> Void
    var onNewCrate: (Record?) -> Void
    var onRenameCrate: (Crate) -> Void
    var onEndPrompt: () -> Void

    /// Push (a crate opens) slides the list in from the right and the grid
    /// out to the left; pop reverses both.
    private func go(_ filter: CrateFilter?) {
        withAnimation(.easeInOut(duration: 0.28)) { nav.filter = filter }
    }

    var body: some View {
        ZStack {
            if let filter = nav.filter {
                RecordListView(filter: filter, library: library, downloads: downloads,
                               onBack: { go(nil) },
                               onRetry: onRetry, onUpdateAndRetry: onUpdateAndRetry,
                               onRemove: onRemove, onNewCrate: onNewCrate)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            } else {
                CrateListView(library: library, downloads: downloads, onOpen: { go($0) },
                              onNew: { onNewCrate(nil) }, onRename: onRenameCrate,
                              onRetry: onRetry, onUpdateAndRetry: onUpdateAndRetry,
                              onRemove: onRemove, onNewCrate: onNewCrate)
                    .transition(.move(edge: .leading))
            }
            if let p = prompt.current {
                NamePromptView(prompt: p, onCancel: onEndPrompt) { name in
                    p.commit(name)
                    onEndPrompt()
                }
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .frame(width: 340, height: 440)
        .clipped()
        .animation(.easeOut(duration: 0.18), value: prompt.current == nil)
    }
}

/// The in-panel modal: a card over the content asking for one name.
struct NamePromptView: View {
    let prompt: PromptState.Prompt
    var onCancel: () -> Void
    var onCommit: (String) -> Void
    @State private var text: String
    @FocusState private var focused: Bool

    init(prompt: PromptState.Prompt, onCancel: @escaping () -> Void, onCommit: @escaping (String) -> Void) {
        self.prompt = prompt
        self.onCancel = onCancel
        self.onCommit = onCommit
        _text = State(initialValue: prompt.initial)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .onTapGesture(perform: onCancel)
            VStack(alignment: .leading, spacing: 12) {
                Text(prompt.title.uppercased())
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .kerning(2.5)
                if !prompt.subtitle.isEmpty {
                    Text(prompt.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                TextField("Crate name", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(focused ? Color.cratesAmber.opacity(0.7) : Color.primary.opacity(0.12), lineWidth: 1))
                    .focused($focused)
                    .onSubmit(commit)
                HStack(spacing: 10) {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                    Button(action: commit) {
                        Text(prompt.button)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(white: 0.1))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.cratesAmber.opacity(trimmed.isEmpty ? 0.45 : 1)))
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmed.isEmpty)
                }
            }
            .padding(18)
            .frame(width: 280)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThickMaterial))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
        }
        .onAppear { DispatchQueue.main.async { focused = true } }
        .onExitCommand(perform: onCancel)
    }

    private func commit() {
        guard !trimmed.isEmpty else { return }
        onCommit(trimmed)
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
    var onRetry: (Record) -> Void
    var onUpdateAndRetry: (Record) -> Void
    var onRemove: (Record) -> Void
    var onNewCrate: (Record?) -> Void

    @AppStorage("recordSort") private var sort = "date"          // date | bpm | key
    @AppStorage("recordSubfilter") private var subfilter = "all" // all | sorted | unsorted (All crate only)
    @State private var hoverBack = false

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

    /// Breadcrumb: CRATES / <this crate>. The first word is the way back.
    private var header: some View {
        HStack(spacing: 7) {
            Button(action: onBack) {
                Text("CRATES")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .kerning(2.5)
            }
            .buttonStyle(.plain)
            .foregroundStyle(hoverBack ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .onHover { hoverBack = $0 }
            .help("Back to your crates")
            Text("/")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text(title.uppercased())
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .kerning(2.5)
                .lineLimit(1)
            Spacer()
            Text("\(records.count) \(records.count == 1 ? "record" : "records")")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Chips, not menus: All · Sorted · Unsorted on the left (All crate only),
    /// DATE · BPM · KEY on the right.
    private var toolbar: some View {
        HStack(spacing: 6) {
            if filter == .all {
                ForEach([("all", "All"), ("sorted", "Sorted"), ("unsorted", "Unsorted")], id: \.0) { value, label in
                    chip(label, on: subfilter == value) { subfilter = value }
                }
            }
            Spacer()
            ForEach([("date", "DATE"), ("bpm", "BPM"), ("key", "KEY")], id: \.0) { value, label in
                chip(label, on: sort == value) { sort = value }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func chip(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
            .kerning(1.2)
            .foregroundStyle(on ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.primary.opacity(on ? 0.12 : 0)))
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
