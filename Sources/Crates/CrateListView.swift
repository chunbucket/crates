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
                CrateIcon(sleeves: sleeves, size: 78)
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

/// A milk crate seen from the front, records standing in it: the first
/// three sleeves peek out over the rim.
struct CrateIcon: View {
    var sleeves: [Record]
    var size: CGFloat = 78
    var tint: Color = Color(white: 0.30)

    var body: some View {
        let w = size, h = size
        let boxTop = h * 0.42, boxH = h - boxTop
        ZStack(alignment: .top) {
            // records standing behind the front face
            HStack(spacing: -w * 0.16) {
                ForEach(0..<max(1, min(3, sleeves.count)), id: \.self) { i in
                    let record = i < sleeves.count ? sleeves[i] : nil
                    MiniVinyl(artPath: record?.artPath)
                        .frame(width: w * 0.46, height: w * 0.46)
                        .offset(y: CGFloat(i % 2) * 3)
                        .opacity(record == nil ? 0.25 : 1)
                }
            }
            .padding(.top, h * 0.06)

            // the crate front
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(LinearGradient(colors: [tint.opacity(1), tint.opacity(0.62)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                // rim
                VStack {
                    Rectangle().fill(Color.white.opacity(0.14)).frame(height: 5)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                // slats
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { _ in
                        Spacer()
                        Rectangle().fill(Color.black.opacity(0.28)).frame(width: 1.5)
                    }
                    Spacer()
                }
                .padding(.vertical, 9)
                // handle slot
                Capsule().fill(Color.black.opacity(0.42)).frame(width: w * 0.30, height: 5).offset(y: -boxH * 0.20)
            }
            .frame(width: w, height: boxH)
            .padding(.top, boxTop)
            .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
        }
        .frame(width: w, height: h)
    }
}
