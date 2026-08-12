import Foundation

/// JSON-backed index of every finished cut, plus the running cut counter.
final class Library: ObservableObject {
    @Published private(set) var cuts: [Cut] = []

    static let supportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Cuts", isDirectory: true)
    }()
    static let artDir = supportDir.appendingPathComponent("art", isDirectory: true)
    private static let indexURL = supportDir.appendingPathComponent("library.json")

    static let destinationDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("ency_me/making music/song samples/full songs", isDirectory: true)
    }()

    init() {
        try? FileManager.default.createDirectory(at: Self.artDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: Self.destinationDir, withIntermediateDirectories: true)
        load()
    }

    var nextCutNumber: Int { (cuts.map(\.cutNumber).max() ?? 0) + 1 }

    func add(_ cut: Cut) {
        cuts.insert(cut, at: 0)
        save()
    }

    func remove(_ cut: Cut) {
        cuts.removeAll { $0.id == cut.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.indexURL),
              let decoded = try? JSONDecoder().decode([Cut].self, from: data) else { return }
        cuts = decoded.sorted { $0.cutNumber > $1.cutNumber }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(cuts) else { return }
        try? data.write(to: Self.indexURL, options: .atomic)
    }
}
