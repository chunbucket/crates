import SwiftUI

/// The root of the panel: All, Unsorted, then the user's crates, newest
/// first, and a line to make a new one.
struct CrateListView: View {
    @ObservedObject var library: Library
    var onOpen: (CrateFilter) -> Void

    @State private var newName = ""
    @State private var renaming: UUID?
    @State private var renameText = ""
    @FocusState private var focusedNew: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("CRATES")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .kerning(2.5)
                Spacer()
                Text("\(library.records.count) records")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider().opacity(0.4)

            ScrollView {
                LazyVStack(spacing: 0) {
                    CrateRow(name: "All", count: library.records.count,
                             sleeves: Array(library.records.prefix(3))) { onOpen(.all) }
                    Divider().opacity(0.25)
                    CrateRow(name: "Unsorted", count: library.count(in: .unsorted),
                             sleeves: Array(library.records(in: .unsorted).prefix(3))) { onOpen(.unsorted) }
                    Divider().opacity(0.25)
                    ForEach(library.crates) { crate in
                        if renaming == crate.id {
                            nameField(text: $renameText, placeholder: crate.name) {
                                let name = renameText.trimmingCharacters(in: .whitespaces)
                                if !name.isEmpty { library.renameCrate(crate.id, to: name) }
                                renaming = nil
                            }
                        } else {
                            CrateRow(name: crate.name, count: crate.recordIDs.count,
                                     sleeves: Array(library.records(in: .crate(crate.id)).prefix(3))) { onOpen(.crate(crate.id)) }
                            .contextMenu {
                                Button("Rename…") { renameText = crate.name; renaming = crate.id }
                                Divider()
                                Button("Delete Crate (records stay)") { library.deleteCrate(crate.id) }
                            }
                        }
                        Divider().opacity(0.25)
                    }
                    nameField(text: $newName, placeholder: "+ New Crate", focus: $focusedNew) {
                        let name = newName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        library.addCrate(named: name)
                        newName = ""
                    }
                }
            }
        }
        .frame(width: 340, height: 440)
    }

    private func nameField(text: Binding<String>, placeholder: String,
                           focus: FocusState<Bool>.Binding? = nil, onCommit: @escaping () -> Void) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "shippingbox")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .frame(width: 44, height: 36)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, weight: .semibold))
                .onSubmit(onCommit)
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

/// A crate line: up to three of its sleeves fanned out, name, count.
struct CrateRow: View {
    let name: String
    let count: Int
    let sleeves: [Record]
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 11) {
                ZStack {
                    if sleeves.isEmpty {
                        MiniVinyl(artPath: nil).frame(width: 30, height: 30).opacity(0.5)
                    }
                    ForEach(Array(sleeves.enumerated()), id: \.element.id) { i, record in
                        MiniVinyl(artPath: record.artPath)
                            .frame(width: 30, height: 30)
                            .offset(x: CGFloat(i) * 7 - 7)
                            .zIndex(Double(sleeves.count - i))
                    }
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Text("\(count) \(count == 1 ? "record" : "records")")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.06) : .clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
