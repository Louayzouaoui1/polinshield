import Foundation
import CoreServices

/// Instant detection: watches folders with FSEvents and checks every file the moment it is
/// written, instead of waiting for the next scheduled scan.
final class LiveFileWatcher {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "dev.polinshield.watcher", qos: .utility)
    private let onFinding: (String) -> Void
    private let roots: [String]
    private var lastSeen: [String: Date] = [:]

    init(roots: [String], onFinding: @escaping (String) -> Void) {
        self.roots = roots
        self.onFinding = onFinding
    }

    func start() {
        guard stream == nil else { return }
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let watcher = Unmanaged<LiveFileWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            for i in 0..<min(count, list.count) { watcher.handle(list[i], flags: flags[i]) }
        }
        let create = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
                            | kFSEventStreamCreateFlagNoDefer)
        guard let s = FSEventStreamCreate(kCFAllocatorDefault, callback, &ctx, roots as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5, create) else { return }
        stream = s
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s); FSEventStreamInvalidate(s); FSEventStreamRelease(s)
        stream = nil
    }

    private func handle(_ path: String, flags: FSEventStreamEventFlags) {
        let isFile = flags & UInt32(kFSEventStreamEventFlagItemIsFile) != 0
        let changed = flags & UInt32(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemModified
                                     | kFSEventStreamEventFlagItemRenamed) != 0
        guard isFile, changed else { return }
        let now = Date()
        if let t = lastSeen[path], now.timeIntervalSince(t) < 5 { return }
        lastSeen[path] = now
        if lastSeen.count > 5000 { lastSeen = lastSeen.filter { now.timeIntervalSince($0.value) < 5 } }
        for finding in Self.checkAndClean(path: path) { onFinding(finding) }
    }

    // MARK: - Checks (same rules as scan-malware.sh and the org guard)

    private static let skipped = ["/node_modules/", "/.git/", "/dist/", "/build/", "/Library/", "/.Trash/", "/PolinShield/Quarantine/"]
    private static let codeExts: Set<String> = ["js", "mjs", "cjs", "ts", "tsx", "jsx", "json"]
    private static let fontExts: Set<String> = ["woff", "woff2", "ttf", "eot", "fml"]
    private static let markers = try! NSRegularExpression(pattern:
        #"global\.i\s*=|global\['_V'\]|global\['r'\]=require|RPC_ENDPOINTS|/0x/clb|verify-human|166\.88\.|rmcej%otb%|auth-con-firm\.vercel\.app|auth-rho-dun\.vercel\.app"#)
    private static let padded = try! NSRegularExpression(pattern: #"[ \t]{80,}[^ \t]"#)
    private static let obfuscation = try! NSRegularExpression(pattern: #"_0x[0-9a-f]{4,}|require\(|eval\(|fromCharCode|atob\("#)
    private static let launcher = try! NSRegularExpression(pattern:
        #"node\s+[^|;&"]*\.(fml|woff2?|ttf|eot|txt|png|jpe?g|svg|ico)"#)

    enum Kind { case fakeFont, launcher, padded, marker }

    /// Detects, then cleans: whole-file payloads (fake fonts, folderOpen launchers) are moved to
    /// quarantine; a padded payload appended to real code is cut off at the padding; marker lines
    /// are removed from *config* files. Every original is saved in quarantine first, nothing is deleted.
    static func checkAndClean(path: String) -> [String] {
        guard let (data, text, kinds) = analyze(path: path), !kinds.isEmpty else { return [] }
        let labels: [Kind: String] = [.fakeFont: "fake font", .launcher: "folderOpen launcher",
                                      .padded: "padded obfuscated payload", .marker: "malware marker"]
        let what = kinds.compactMap { labels[$0] }.sorted().joined(separator: ", ")
        guard let backup = saveToQuarantine(path: path, data: data) else {
            return ["🚨 \(what) in \(path), COULD NOT quarantine: remove it by hand"]
        }
        let fm = FileManager.default
        if kinds.contains(.fakeFont) || kinds.contains(.launcher) {
            try? fm.removeItem(atPath: path)
            return ["🚨 \(what) quarantined: \(path)"]
        }
        guard let text else { return ["🚨 \(what) in \(path), original saved to \(backup)"] }
        var lines = text.components(separatedBy: "\n")
        for (n, line) in lines.enumerated() {
            let r = NSRange(line.startIndex..., in: line)
            if line.utf8.count > 1000, padded.firstMatch(in: line, range: r) != nil,
               obfuscation.firstMatch(in: line, range: r) != nil,
               let cut = padded.firstMatch(in: line, range: r),
               let range = Range(cut.range, in: line) {
                lines[n] = String(line[..<range.lowerBound])
            }
        }
        if kinds.contains(.marker), URL(fileURLWithPath: path).lastPathComponent.lowercased().contains("config") {
            lines.removeAll { markers.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
        }
        let cleaned = lines.joined(separator: "\n")
        guard cleaned != text, let out = cleaned.data(using: .isoLatin1) else {
            return ["🚨 \(what) in \(path), not auto-cleaned (original untouched; copy in \(backup))"]
        }
        do { try out.write(to: URL(fileURLWithPath: path)) } catch { return ["🚨 \(what) in \(path), clean failed: \(error.localizedDescription)"] }
        return ["🚨 \(what) removed from \(path) (original in quarantine)"]
    }

    private static func saveToQuarantine(path: String, data: Data) -> String? {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PolinShield/Quarantine")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        let name = "\(stamp)-\(URL(fileURLWithPath: path).lastPathComponent)"
        let dest = dir.appendingPathComponent(name)
        do {
            try data.write(to: dest)
            try "\(path)\n".write(to: dir.appendingPathComponent(name + ".origin"), atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)
            return dest.path
        } catch { return nil }
    }

    static func analyze(path: String) -> (Data, String?, Set<Kind>)? {
        guard !skipped.contains(where: { path.contains($0) }) else { return nil }
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        let isTasks = path.hasSuffix("/.vscode/tasks.json")
        guard codeExts.contains(ext) || fontExts.contains(ext) || isTasks else { return nil }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int, size > 0, size < 5_000_000,
              let data = try? Data(contentsOf: url) else { return nil }
        var kinds = Set<Kind>()
        if ext == "fml" { kinds.insert(.fakeFont) }
        if ["woff", "woff2", "ttf"].contains(ext) {
            let magic = data.prefix(4).map { String(format: "%02x", $0) }.joined()
            let valid: [String: [String]] = ["woff": ["774f4646"], "woff2": ["774f4632"],
                                              "ttf": ["00010000", "74727565", "4f54544f"]]
            if !(valid[ext] ?? []).contains(magic) { kinds.insert(.fakeFont) }
        }
        guard let text = String(data: data, encoding: .isoLatin1) else { return (data, nil, kinds) }
        let whole = NSRange(text.startIndex..., in: text)
        if markers.firstMatch(in: text, range: whole) != nil { kinds.insert(.marker) }
        if isTasks, text.contains("folderOpen"), launcher.firstMatch(in: text, range: whole) != nil { kinds.insert(.launcher) }
        if codeExts.contains(ext), data.count > 1000 {
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) where line.utf8.count > 1000 {
                let l = String(line); let r = NSRange(l.startIndex..., in: l)
                if padded.firstMatch(in: l, range: r) != nil, obfuscation.firstMatch(in: l, range: r) != nil {
                    kinds.insert(.padded); break
                }
            }
        }
        return (data, text, kinds)
    }
}
