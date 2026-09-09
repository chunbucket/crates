import Foundation

/// Row status on disk. Plain strings (house style: no enum types) so the
/// index stays a simple document for other front ends to read.
enum RecordStatus {
    static let filed = "filed"
    static let failed = "failed"
}

struct Record: Identifiable, Equatable {
    let id: UUID
    let number: Int
    let url: String
    var title: String
    var uploader: String
    var status: String = RecordStatus.filed
    var error: String?
    var filePath: String?
    var artPath: String?
    var duration: Double?
    let date: Date

    var isFailed: Bool { status == RecordStatus.failed }
    var fileURL: URL? { filePath.map { URL(fileURLWithPath: $0) } }
    var artURL: URL? { artPath.map { URL(fileURLWithPath: $0) } }
    /// The FLAC is where the index says it is.
    var fileExists: Bool { filePath.map { FileManager.default.fileExists(atPath: $0) } ?? false }

    var durationLabel: String {
        guard let d = duration, d > 0 else { return "—:—" }
        let s = Int(d.rounded())
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    var numberLabel: String { String(format: "RECORD Nº %03d", number) }

    var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MM · dd · yy"
        return f.string(from: date)
    }
}

/// Hand-written Codable so v0.1 index files (no status/error, filePath
/// always present) load unchanged, and so a failed row is written with
/// `"filePath": ""` — older builds then still read the file instead of
/// treating it as corrupt.
extension Record: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, url, title, uploader, status, error, filePath, artPath, duration, date
        case number = "cutNumber"   // on-disk key from v0.1; the Swift name moved on
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        number = try c.decode(Int.self, forKey: .number)
        url = try c.decode(String.self, forKey: .url)
        title = try c.decode(String.self, forKey: .title)
        uploader = try c.decodeIfPresent(String.self, forKey: .uploader) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? RecordStatus.filed
        error = try c.decodeIfPresent(String.self, forKey: .error)
        let path = try c.decodeIfPresent(String.self, forKey: .filePath) ?? ""
        filePath = path.isEmpty ? nil : path
        artPath = try c.decodeIfPresent(String.self, forKey: .artPath)
        duration = try c.decodeIfPresent(Double.self, forKey: .duration)
        date = try c.decode(Date.self, forKey: .date)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(number, forKey: .number)
        try c.encode(url, forKey: .url)
        try c.encode(title, forKey: .title)
        try c.encode(uploader, forKey: .uploader)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(error, forKey: .error)
        try c.encode(filePath ?? "", forKey: .filePath)
        try c.encodeIfPresent(artPath, forKey: .artPath)
        try c.encodeIfPresent(duration, forKey: .duration)
        try c.encode(date, forKey: .date)
    }
}

enum RecordPhase: Equatable {
    case fetchingArt          // oEmbed + thumbnail
    case cutting(Double)      // downloading, 0...1
    case pressing             // ffmpeg convert / embed
    case done
    case failed(String)

    /// Finished one way or the other — nothing left in flight.
    var isTerminal: Bool {
        switch self {
        case .done, .failed: return true
        default: return false
        }
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// A download in flight, displayed on the shelf.
final class ActiveRecord: ObservableObject, Identifiable {
    let id: UUID
    let url: String
    let number: Int
    let date = Date()
    @Published var title: String
    @Published var uploader: String = ""
    @Published var artPath: String?
    @Published var phase: RecordPhase = .fetchingArt

    static let placeholderTitle = "Fetching…"

    /// `id`/`number` are reused when retrying a failed row so the row is
    /// replaced in place rather than duplicated.
    init(url: String, number: Int, id: UUID) {
        self.id = id
        self.url = url
        self.number = number
        self.title = Self.placeholderTitle
    }

    /// oEmbed came back with a real title.
    var hasTitle: Bool { title != Self.placeholderTitle }

    var numberLabel: String { String(format: "RECORD Nº %03d", number) }
    var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MM · dd · yy"
        return f.string(from: date)
    }
}
