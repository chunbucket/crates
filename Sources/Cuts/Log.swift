import Foundation

/// Tiny append-only debug log: ~/Library/Application Support/Cuts/debug.log
enum Log {
    private static let url = Library.supportDir.appendingPathComponent("debug.log")
    private static let queue = DispatchQueue(label: "cuts.log")
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func d(_ msg: String) {
        queue.async {
            let line = "\(stamp.string(from: Date())) \(msg)\n"
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(line.data(using: .utf8)!)
                try? h.close()
            } else {
                try? line.data(using: .utf8)!.write(to: url)
            }
        }
    }
}
