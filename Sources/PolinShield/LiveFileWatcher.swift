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
        for finding in Self.check(path: path) { onFinding(finding) }
    }

    // MARK: - Checks (same rules as scan-malware.sh and the org guard)

    private static let skipped = ["/node_modules/", "/.git/", "/dist/", "/build/", "/Library/", "/.Trash/"]
    private static let codeExts: Set<String> = ["js", "mjs", "cjs", "ts", "tsx", "jsx", "json"]
    private static let fontExts: Set<String> = ["woff", "woff2", "ttf", "eot", "fml"]
    private static let markers = try! NSRegularExpression(pattern:
        #"global\.i\s*=|global\['_V'\]|global\['r'\]=require|RPC_ENDPOINTS|/0x/clb|verify-human|166\.88\.|rmcej%otb%|auth-con-firm\.vercel\.app|auth-rho-dun\.vercel\.app"#)
    private static let padded = try! NSRegularExpression(pattern: #"[ \t]{80,}[^ \t]"#)
    private static let obfuscation = try! NSRegularExpression(pattern: #"_0x[0-9a-f]{4,}|require\(|eval\(|fromCharCode|atob\("#)
    private static let launcher = try! NSRegularExpression(pattern:
        #"node\s+[^|;&"]*\.(fml|woff2?|ttf|eot|txt|png|jpe?g|svg|ico)"#)

    static func check(path: String) -> [String] {
        guard !skipped.contains(where: { path.contains($0) }) else { return [] }
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        let isTasks = path.hasSuffix("/.vscode/tasks.json")
        guard codeExts.contains(ext) || fontExts.contains(ext) || isTasks else { return [] }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int, size > 0, size < 5_000_000,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [] }
        var out: [String] = []

        if ext == "fml" { out.append("🚨 Fake font (.fml) written: \(path)") }
        if ["woff", "woff2", "ttf"].contains(ext) {
            let magic = data.prefix(4).map { String(format: "%02x", $0) }.joined()
            let valid: [String: [String]] = ["woff": ["774f4646"], "woff2": ["774f4632"],
                                              "ttf": ["00010000", "74727565", "4f54544f"]]
            if !(valid[ext] ?? []).contains(magic) { out.append("🚨 Fake font (not a real \(ext)) written: \(path)") }
        }
        guard let text = String(data: data, encoding: .isoLatin1) else { return out }
        let whole = NSRange(text.startIndex..., in: text)
        if markers.firstMatch(in: text, range: whole) != nil { out.append("🚨 Malware marker in: \(path)") }
        if isTasks, text.contains("folderOpen"), launcher.firstMatch(in: text, range: whole) != nil {
            out.append("🚨 VS Code folderOpen task launching node on a non-script file: \(path)")
        }
        if codeExts.contains(ext), data.count > 1000 {
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) where line.utf8.count > 1000 {
                let s = String(line); let r = NSRange(s.startIndex..., in: s)
                if padded.firstMatch(in: s, range: r) != nil, obfuscation.firstMatch(in: s, range: r) != nil {
                    out.append("🚨 Padded obfuscated line in: \(path)"); break
                }
            }
        }
        return out
    }
}
