import Foundation

/// JSON-backed index of every record (filed or failed), plus the running counter.
final class Library: ObservableObject {
    @Published private(set) var records: [Record] = []

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
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.indexURL) else { return }
        do {
            records = try JSONDecoder().decode([Record].self, from: data).sorted(by: Self.newestFirst)
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
        guard let data = try? enc.encode(records) else { return }
        try? data.write(to: Self.indexURL, options: .atomic)
    }
}
