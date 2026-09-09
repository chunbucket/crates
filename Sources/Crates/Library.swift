import Foundation

/// On disk: `{ "version": 2, "records": [...], "crates": [...] }`. v0.2 wrote a
/// bare array of records; `load` still reads that.
private struct LibraryFile: Codable {
    var version: Int
    var records: [Record]
    var crates: [Crate]
}

/// JSON-backed index of every record (filed or failed), the user's crates,
/// and the running record counter.
final class Library: ObservableObject {
    @Published private(set) var records: [Record] = []
    @Published private(set) var crates: [Crate] = []

    static let supportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Crates", isDirectory: true)
        // v0.2 was called Cuts: adopt its folder (index, art, logs) when this
        // one doesn't exist yet. No logging here — Log itself needs this path.
        let legacy = base.appendingPathComponent("Cuts", isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path), fm.fileExists(atPath: legacy.path) {
            migratedFromCuts = (try? fm.moveItem(at: legacy, to: dir)) != nil
        }
        return dir
    }()
    private static var migratedFromCuts = false
    static let artDir = supportDir.appendingPathComponent("art", isDirectory: true)
    private static let indexURL = supportDir.appendingPathComponent("library.json")

    init() {
        try? FileManager.default.createDirectory(at: Self.artDir, withIntermediateDirectories: true)
        if Self.migratedFromCuts { Log.d("migrated Application Support/Cuts → Crates") }
        load()
    }

    /// Failed rows keep their number, so numbering stays monotonic.
    var nextNumber: Int { (records.map(\.number).max() ?? 0) + 1 }

    private static let newestFirst: (Record, Record) -> Bool = { $0.number > $1.number }

    /// Insert, or replace the row with the same id (a retried record lands in
    /// the same slot with the same CUT Nº).
    func upsert(_ record: Record) {
        records.removeAll { $0.id == record.id }
        records.append(record)
        records.sort(by: Self.newestFirst)
        save()
    }

    func remove(_ record: Record) {
        records.removeAll { $0.id == record.id }
        for i in crates.indices { crates[i].recordIDs.removeAll { $0 == record.id } }
        save()
    }

    // MARK: - Crates

    @discardableResult
    func addCrate(named name: String) -> Crate {
        let crate = Crate(name: name)
        crates.insert(crate, at: 0)
        save()
        return crate
    }

    func renameCrate(_ id: UUID, to name: String) {
        guard let i = crates.firstIndex(where: { $0.id == id }) else { return }
        crates[i].name = name
        save()
    }

    /// Records stay; only the crate goes.
    func deleteCrate(_ id: UUID) {
        crates.removeAll { $0.id == id }
        save()
    }

    func crate(_ id: UUID) -> Crate? { crates.first { $0.id == id } }

    func add(_ record: Record, to crateID: UUID) {
        guard let i = crates.firstIndex(where: { $0.id == crateID }),
              !crates[i].recordIDs.contains(record.id) else { return }
        crates[i].recordIDs.append(record.id)
        save()
    }

    func remove(_ record: Record, from crateID: UUID) {
        guard let i = crates.firstIndex(where: { $0.id == crateID }) else { return }
        crates[i].recordIDs.removeAll { $0 == record.id }
        save()
    }

    func crates(containing record: Record) -> [Crate] {
        crates.filter { $0.recordIDs.contains(record.id) }
    }

    /// In at least one crate.
    func isSorted(_ record: Record) -> Bool {
        crates.contains { $0.recordIDs.contains(record.id) }
    }

    func records(in filter: CrateFilter) -> [Record] {
        switch filter {
        case .all: return records
        case .unsorted: return records.filter { !isSorted($0) }
        case .crate(let id):
            guard let ids = crate(id)?.recordIDs else { return [] }
            let set = Set(ids)
            return records.filter { set.contains($0.id) }
        }
    }

    func count(in filter: CrateFilter) -> Int { records(in: filter).count }

    private func load() {
        guard let data = try? Data(contentsOf: Self.indexURL) else { return }
        do {
            let decoder = JSONDecoder()
            if let file = try? decoder.decode(LibraryFile.self, from: data) {
                records = file.records.sorted(by: Self.newestFirst)
                crates = file.crates
            } else {
                // v0.2: a bare array, no crates.
                records = try decoder.decode([Record].self, from: data).sorted(by: Self.newestFirst)
                Log.d("library.json upgraded from the v0.2 array to v2")
                save()
            }
        } catch {
            // Never silently start over at CUT Nº 001 on top of a damaged
            // index — park it where it can be recovered and log why.
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = Self.supportDir.appendingPathComponent("library.corrupt-\(stamp).json")
            try? FileManager.default.moveItem(at: Self.indexURL, to: backup)
            Log.d("library.json unreadable (\(error)); moved to \(backup.lastPathComponent)")
        }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(LibraryFile(version: 2, records: records, crates: crates)) else { return }
        try? data.write(to: Self.indexURL, options: .atomic)
    }
}
