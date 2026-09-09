import Foundation

/// Once a day, ask GitHub for the latest release and remember whether it is
/// newer than this build. Nothing installs itself: the menu offers the
/// download page, and the user is told once per version.
final class UpdateCheck: ObservableObject {
    static let shared = UpdateCheck()

    static let repo = ProcessInfo.processInfo.environment["CRATES_UPDATE_REPO"] ?? "chunbucket/crates"
    static let downloadPage = URL(string: "https://ency.world/crates")!
    private static let stampKey = "lastUpdateCheck"
    private static let notifiedKey = "lastNotifiedVersion"

    /// A newer version's number, when there is one.
    @Published private(set) var available: String?
    var onAvailable: ((String) -> Void)?
    private var timer: Timer?

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.checkIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.checkIfDue()
        }
    }

    func checkIfDue(force: Bool = false) {
        let last = UserDefaults.standard.double(forKey: Self.stampKey)
        guard force || Date().timeIntervalSince1970 - last > 24 * 3600 else { return }
        check()
    }

    private func check() {
        let mine = Settings.appVersion
        guard mine != "dev" else { return }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Crates/\(mine)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = obj["tag_name"] as? String else {
                Log.d("update check failed: \(error?.localizedDescription ?? "no release")")
                return
            }
            DispatchQueue.main.async {
                guard let self else { return }
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.stampKey)
                let latest = Self.version(from: tag)
                Log.d("update check: latest \(latest), running \(mine)")
                guard Self.isNewer(latest, than: mine) else { self.available = nil; return }
                self.available = latest
                if UserDefaults.standard.string(forKey: Self.notifiedKey) != latest {
                    UserDefaults.standard.set(latest, forKey: Self.notifiedKey)
                    self.onAvailable?(latest)
                }
            }
        }.resume()
    }

    /// "v0.3.1" → "0.3.1"
    static func version(from tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// Numeric, component-wise: 0.10.0 is newer than 0.9.9.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
