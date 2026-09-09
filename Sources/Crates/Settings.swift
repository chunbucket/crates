import AppKit
import SwiftUI
import ServiceManagement

/// What "Remove from Shelf" does with the FLAC. Strings on purpose (plain
/// UserDefaults values).
enum RemovePolicy {
    static let ask = "ask"
    static let keep = "keep"
    static let trash = "trash"
}

/// User preferences, UserDefaults-backed. Paths are stored as plain strings
/// (no bookmarks) so the index and settings stay portable.
final class Settings: ObservableObject {
    static let shared = Settings()

    private static let destinationKey = "destinationDir"
    private static let removePolicyKey = "removePolicy"
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    /// Fresh-install default.
    static let defaultDestination = home.appendingPathComponent("Music/Crates", isDirectory: true)
    /// v0.1 hardcoded the owner's sample folder; adopt it when it's there and
    /// nothing has been chosen yet, so an upgrade doesn't move the library.
    static let legacyDestination = home.appendingPathComponent(
        "ency_me/making music/song samples/full songs", isDirectory: true)

    @Published var destinationDir: URL {
        didSet { UserDefaults.standard.set(destinationDir.path, forKey: Self.destinationKey) }
    }
    /// Read from launchd on demand (an XPC round-trip) — only the Settings form asks.
    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    @Published var removePolicy: String {
        didSet { UserDefaults.standard.set(removePolicy, forKey: Self.removePolicyKey) }
    }

    private init() {
        // v0.2 was called Cuts: bring its preferences over once.
        if UserDefaults.standard.string(forKey: Self.destinationKey) == nil,
           let old = UserDefaults(suiteName: "me.ency.cuts") {
            for key in [Self.destinationKey, Self.removePolicyKey, "hasLaunched", "lastNotifiedVersion"] {
                if let value = old.object(forKey: key) { UserDefaults.standard.set(value, forKey: key) }
            }
        }
        if let stored = UserDefaults.standard.string(forKey: Self.destinationKey) {
            destinationDir = URL(fileURLWithPath: stored, isDirectory: true)
        } else if FileManager.default.fileExists(atPath: Self.legacyDestination.path) {
            destinationDir = Self.legacyDestination
        } else {
            destinationDir = Self.defaultDestination
        }
        removePolicy = UserDefaults.standard.string(forKey: Self.removePolicyKey) ?? RemovePolicy.ask
    }

    func setLaunchAtLogin(_ on: Bool) {
        objectWillChange.send()
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.d("launch at login \(on ? "register" : "unregister") failed: \(error)")
        }
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}

/// Plain macOS settings form. The dubplate styling stays on the shelf and
/// collection; this is system chrome on purpose.
struct SettingsView: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var tools = Tools.shared
    @State private var updating = false
    @State private var updateNote: String?

    var body: some View {
        Form {
            LabeledContent("Records go to") {
                HStack(spacing: 8) {
                    Text((settings.destinationDir.path as NSString).abbreviatingWithTildeInPath)
                        .truncationMode(.middle)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Button("Choose…", action: chooseDestination)
                }
            }
            Toggle("Launch at login", isOn: Binding(
                get: { settings.launchAtLogin },
                set: { settings.setLaunchAtLogin($0) }))
            LabeledContent("yt-dlp") {
                HStack(spacing: 8) {
                    Text(updateNote ?? tools.ytdlpVersion)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if updating {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Update", action: updateYtdlp)
                    }
                }
            }
            Picker("Removing a record", selection: $settings.removePolicy) {
                Text("Ask each time").tag(RemovePolicy.ask)
                Text("Keep the file").tag(RemovePolicy.keep)
                Text("Move the file to Trash").tag(RemovePolicy.trash)
            }
            LabeledContent("Crates") { Text(Settings.appVersion).foregroundStyle(.secondary) }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.destinationDir
        panel.prompt = "Use This Folder"
        if panel.runModal() == .OK, let url = panel.url {
            settings.destinationDir = url
        }
    }

    private func updateYtdlp() {
        updating = true
        updateNote = "updating…"
        tools.updateYtdlp { result in
            updating = false
            switch result {
            case .success(let version): updateNote = "updated · \(version)"
            case .failure(let error): updateNote = "update failed — \(error.localizedDescription)"
            }
        }
    }
}

/// One settings window, created on first use, brought forward after that.
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let host = NSHostingView(rootView: SettingsView())
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 220),
                             styleMask: [.titled, .closable],
                             backing: .buffered, defer: false)
            w.title = "Crates Settings"
            w.contentView = host
            w.setContentSize(host.fittingSize)
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
