import Foundation

struct Cut: Codable, Identifiable, Equatable {
    let id: UUID
    let cutNumber: Int
    let url: String
    var title: String
    var uploader: String
    var filePath: String
    var artPath: String?
    var duration: Double?
    let date: Date

    var fileURL: URL { URL(fileURLWithPath: filePath) }
    var artURL: URL? { artPath.map { URL(fileURLWithPath: $0) } }

    var durationLabel: String {
        guard let d = duration, d > 0 else { return "—:—" }
        let s = Int(d.rounded())
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    var cutLabel: String { String(format: "CUT Nº %03d", cutNumber) }

    var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MM · dd · yy"
        return f.string(from: date)
    }
}

enum CutPhase: Equatable {
    case fetchingArt          // oEmbed + thumbnail
    case cutting(Double)      // downloading, 0...1
    case pressing             // ffmpeg convert / embed
    case done
    case failed(String)
}

/// A download in flight, displayed on the shelf.
final class ActiveCut: ObservableObject, Identifiable {
    let id = UUID()
    let url: String
    let cutNumber: Int
    let date = Date()
    @Published var title: String
    @Published var uploader: String = ""
    @Published var artPath: String?
    @Published var phase: CutPhase = .fetchingArt

    init(url: String, cutNumber: Int) {
        self.url = url
        self.cutNumber = cutNumber
        self.title = "Fetching…"
    }

    var cutLabel: String { String(format: "CUT Nº %03d", cutNumber) }
    var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MM · dd · yy"
        return f.string(from: date)
    }
}
