import SwiftUI

/// The root of the panel: every crate as an icon in a three-across grid —
/// All and Unsorted first, then the user's crates, newest first.
struct CrateListView: View {
    @ObservedObject var library: Library
    var onOpen: (CrateFilter) -> Void
    var onNew: () -> Void
    var onRename: (Crate) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

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
                LazyVGrid(columns: columns, spacing: 16) {
                    CrateTile(name: "All", count: library.records.count,
                              sleeves: Array(library.records.prefix(3))) { onOpen(.all) }
                    CrateTile(name: "Unsorted", count: library.count(in: .unsorted),
                              sleeves: Array(library.records(in: .unsorted).prefix(3))) { onOpen(.unsorted) }
                    ForEach(library.crates) { crate in
                        CrateTile(name: crate.name, count: crate.recordIDs.count,
                                  sleeves: Array(library.records(in: .crate(crate.id)).prefix(3))) { onOpen(.crate(crate.id)) }
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

/// A crate icon with its name and count under it.
struct CrateTile: View {
    let name: String
    let count: Int
    let sleeves: [Record]
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 7) {
                MilkCrateIcon(sleeves: sleeves, size: 84)
                    .scaleEffect(hovering ? 1.04 : 1)
                    .animation(.spring(duration: 0.25), value: hovering)
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
    }
}
