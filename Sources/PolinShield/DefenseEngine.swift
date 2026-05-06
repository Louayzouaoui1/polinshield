import Foundation
import SwiftUI
import UserNotifications

/// The brain of the app - manages defense state, runs scans, talks to bash scripts
@MainActor
class DefenseEngine: ObservableObject {
    static let shared = DefenseEngine()

    @Published var defenses: [Defense] = Defense.allDefenses
    @Published var scanHistory: [ScanResult] = []
    @Published var forcePushHistory: [ForcePushEvent] = []
    @Published var isScanning = false
    @Published var lastScanDate: Date?

    private var scanTimer: Timer?

    enum OverallStatus { case clean, warning, infected, unknown }

    var overallStatus: OverallStatus {
        if defenses.contains(where: { !$0.installed }) { return .warning }
        if let last = scanHistory.first, last.foundIndicators.isEmpty == false { return .infected }
        if scanHistory.isEmpty { return .unknown }
        return .clean
    }

    var statusIcon: String {
        switch overallStatus {
        case .clean: return "checkmark.shield.fill"
        case .warning: return "exclamationmark.shield.fill"
        case .infected: return "xmark.shield.fill"
        case .unknown: return "shield"
        }
    }

    var statusColor: Color {
        switch overallStatus {
        case .clean: return .green
        case .warning: return .yellow
        case .infected: return .red
        case .unknown: return .secondary
        }
    }

    var statusText: String {
        switch overallStatus {
        case .clean: return "Protected"
        case .warning: return "Defenses incomplete"
        case .infected: return "Infection detected"
        case .unknown: return "No scan yet"
        }
    }

    init() {
        loadHistory()
        loadForcePushHistory()
        startScanTimer()
    }

    func startScanTimer() {
        scanTimer?.invalidate()
        // Hourly force-push check
        scanTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { await self?.checkForcePushes() }
        }
    }

    // MARK: - Defense detection

    func refreshStatus() async {
        for i in defenses.indices {
            defenses[i].installed = await isDefenseInstalled(defenses[i].id)
        }
    }

    func isDefenseInstalled(_ id: Defense.ID) async -> Bool {
        switch id {
        case .npmIgnoreScripts:
            let npmrc = (try? String(contentsOfFile: NSString(string: "~/.npmrc").expandingTildeInPath, encoding: .utf8)) ?? ""
            return npmrc.contains("ignore-scripts=true")
        case .hostsBlock:
            let hosts = (try? String(contentsOfFile: "/etc/hosts", encoding: .utf8)) ?? ""
            return hosts.contains("auth-con-firm.vercel.app")
        case .gitHook:
            let hookPath = NSString(string: "~/.git-hooks/pre-commit").expandingTildeInPath
            return FileManager.default.isExecutableFile(atPath: hookPath)
        case .forcePushWatcher:
            let plistPath = NSString(string: "~/Library/LaunchAgents/dev.polinshield.force-push.plist").expandingTildeInPath
            return FileManager.default.fileExists(atPath: plistPath)
        case .dailyScan:
            let plistPath = NSString(string: "~/Library/LaunchAgents/dev.polinshield.scan.plist").expandingTildeInPath
            return FileManager.default.fileExists(atPath: plistPath)
        }
    }

    // MARK: - Actions

    /// Resolve a script in the bundle's Resources/scripts/ folder
    func scriptPath(_ name: String) -> String? {
        guard let resPath = Bundle.main.resourcePath else { return nil }
        let candidate = "\(resPath)/scripts/\(name).sh"
        return FileManager.default.fileExists(atPath: candidate) ? candidate : nil
    }

    func runScan() async {
        isScanning = true
        defer { isScanning = false }

        guard let scriptPath = scriptPath("scan-malware") else {
            let r = ScanResult(date: Date(), exitCode: -1,
                               foundIndicators: ["🚨 ERROR: scan-malware.sh not found in app bundle"],
                               log: "Bundle resourcePath: \(Bundle.main.resourcePath ?? "nil")")
            scanHistory.insert(r, at: 0)
            return
        }

        let result = await runShell("/bin/bash", args: [scriptPath, NSString(string: "~/Desktop").expandingTildeInPath])
        let indicators = parseIndicators(result.output)
        let scan = ScanResult(date: Date(), exitCode: result.exitCode, foundIndicators: indicators, log: result.output)
        scanHistory.insert(scan, at: 0)
        if scanHistory.count > 100 { scanHistory.removeLast() }
        lastScanDate = Date()
        saveHistory()

        if !indicators.isEmpty {
            sendNotification(title: "🚨 PolinShield: Malware indicators found",
                             body: "\(indicators.count) indicator(s) detected. Open dashboard for details.")
        }
    }

    @Published var lastInstallOutput: String = ""

    func installDefense(_ id: Defense.ID, sudoPassword: String? = nil) async {
        let scriptName: String
        switch id {
        case .npmIgnoreScripts: scriptName = "install-npm-block"
        case .hostsBlock: scriptName = "install-hosts-block"
        case .gitHook: scriptName = "install-git-hook"
        case .forcePushWatcher: scriptName = "install-force-push-watcher"
        case .dailyScan: scriptName = "install-daily-scan"
        }
        guard let path = scriptPath(scriptName) else {
            lastInstallOutput = "ERROR: \(scriptName).sh not found in bundle"
            return
        }
        var args = [path]
        if let pwd = sudoPassword { args.append(pwd) }
        let result = await runShell("/bin/bash", args: args)
        lastInstallOutput = result.output
        await refreshStatus()
    }

    func installAllDefenses(sudoPassword: String) async {
        for defense in defenses where !defense.installed {
            await installDefense(defense.id, sudoPassword: sudoPassword)
        }
    }

    @Published var isCheckingForcePushes = false
    @Published var lastForcePushCheck: Date?

    func checkForcePushes(notify: Bool = true) async {
        guard let path = scriptPath("check-force-pushes") else { return }
        isCheckingForcePushes = true
        defer { isCheckingForcePushes = false; lastForcePushCheck = Date() }

        let result = await runShell("/bin/bash", args: [path])
        let events = parseForcePushOutput(result.output)

        // Merge new events (don't duplicate)
        let existingIDs = Set(forcePushHistory.map { $0.id })
        let newOnes = events.filter { !existingIDs.contains($0.id) }
        forcePushHistory.insert(contentsOf: newOnes, at: 0)
        if forcePushHistory.count > 200 { forcePushHistory = Array(forcePushHistory.prefix(200)) }
        saveForcePushHistory()

        if notify && !newOnes.isEmpty {
            sendNotification(title: "⚠️ Unexpected GitHub force-push detected",
                             body: "\(newOnes.count) force-push(es). Open PolinShield dashboard.")
        }
    }

    func parseForcePushOutput(_ output: String) -> [ForcePushEvent] {
        let formatter = ISO8601DateFormatter()
        var events: [ForcePushEvent] = []
        for line in output.split(separator: "\n") {
            // Format: "ISO_DATE OWNER/REPO/BRANCH BEFORESHA -> AFTERSHA"
            let parts = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 5 else { continue }
            guard let date = formatter.date(from: parts[0]) else { continue }
            let repoBranch = parts[1]
            // Split repo (owner/name) and branch (everything after the third /)
            let slashes = repoBranch.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
            guard slashes.count == 3 else { continue }
            let repo = "\(slashes[0])/\(slashes[1])"
            let branch = slashes[2]
            let beforeSha = parts[2]
            // parts[3] is "->" so head is parts[4]
            let headSha = parts[4]
            events.append(ForcePushEvent(date: date, repo: repo, branch: branch, beforeSha: beforeSha, headSha: headSha))
        }
        return events
    }

    func saveForcePushHistory() {
        let url = supportDir().appendingPathComponent("force-push-history.json")
        if let data = try? JSONEncoder().encode(forcePushHistory) {
            try? data.write(to: url)
        }
    }
    func loadForcePushHistory() {
        let url = supportDir().appendingPathComponent("force-push-history.json")
        if let data = try? Data(contentsOf: url),
           let h = try? JSONDecoder().decode([ForcePushEvent].self, from: data) {
            forcePushHistory = h
        }
    }

    // MARK: - Shell

    struct ShellResult { let output: String; let exitCode: Int32 }
    func runShell(_ path: String, args: [String]) async -> ShellResult {
        await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.launchPath = path
            proc.arguments = args
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            do { try proc.run() } catch { return ShellResult(output: "Failed to launch: \(error)", exitCode: -1) }
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return ShellResult(output: String(data: data, encoding: .utf8) ?? "", exitCode: proc.terminationStatus)
        }.value
    }

    // MARK: - Parsing

    func parseIndicators(_ output: String) -> [String] {
        output.split(separator: "\n")
            .map(String.init)
            .filter { $0.contains("🚨") }
    }

    // MARK: - Persistence

    func saveHistory() {
        let url = supportDir().appendingPathComponent("scan-history.json")
        if let data = try? JSONEncoder().encode(scanHistory) {
            try? data.write(to: url)
        }
    }
    func loadHistory() {
        let url = supportDir().appendingPathComponent("scan-history.json")
        if let data = try? Data(contentsOf: url),
           let h = try? JSONDecoder().decode([ScanResult].self, from: data) {
            scanHistory = h
            lastScanDate = h.first?.date
        }
    }
    func supportDir() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PolinShield")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Notifications

    func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Models

struct Defense: Identifiable, Equatable {
    enum ID: String, Codable, CaseIterable {
        case npmIgnoreScripts = "npm-ignore-scripts"
        case hostsBlock = "hosts-block"
        case gitHook = "git-hook"
        case forcePushWatcher = "force-push-watcher"
        case dailyScan = "daily-scan"
    }
    let id: ID
    let title: String
    let description: String
    let needsSudo: Bool
    var installed: Bool = false

    static let allDefenses: [Defense] = [
        .init(id: .npmIgnoreScripts, title: "Block npm postinstall scripts",
              description: "Prevents the #1 attack vector. Adds ignore-scripts=true to ~/.npmrc.",
              needsSudo: false),
        .init(id: .hostsBlock, title: "Block known C2 servers",
              description: "Adds known attacker domains to /etc/hosts as 0.0.0.0.",
              needsSudo: true),
        .init(id: .gitHook, title: "Global git pre-commit hook",
              description: "Blocks any commit containing known malware signatures.",
              needsSudo: false),
        .init(id: .forcePushWatcher, title: "Hourly force-push detector",
              description: "Polls GitHub for unexpected force-pushes on your account.",
              needsSudo: false),
        .init(id: .dailyScan, title: "Daily 9am malware scan",
              description: "Searches your Desktop for known malware indicators.",
              needsSudo: false),
    ]
}

struct ScanResult: Codable, Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let exitCode: Int32
    let foundIndicators: [String]
    let log: String
    var clean: Bool { foundIndicators.isEmpty }
}

struct ForcePushEvent: Codable, Identifiable, Equatable {
    var id: String { "\(date)-\(repo)-\(branch)" }
    let date: Date
    let repo: String
    let branch: String
    let beforeSha: String
    let headSha: String
}
