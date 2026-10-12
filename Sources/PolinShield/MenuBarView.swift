import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var engine: DefenseEngine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: engine.statusIcon)
                    .foregroundStyle(engine.statusColor)
                    .font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text("PolinShield")
                        .font(.headline)
                    Text(engine.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)

            if !engine.liveAlerts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LIVE DETECTIONS")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(engine.liveAlerts.prefix(5)) { alert in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: alert.cleaned ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(alert.cleaned ? .green : .red)
                                .font(.system(size: 11))
                            VStack(alignment: .leading, spacing: 0) {
                                Text(alert.cleaned ? "CLEANED" : "ACTION NEEDED")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(alert.cleaned ? .green : .red)
                                Text(alert.text.replacingOccurrences(of: "🚨 ", with: ""))
                                    .font(.system(size: 11))
                                    .lineLimit(3)
                            }
                        }
                    }
                    HStack {
                        Button("Open quarantine") {
                            let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                                .appendingPathComponent("PolinShield/Quarantine")
                            NSWorkspace.shared.open(url)
                        }
                        Button("Dismiss") { engine.clearAlerts() }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
                .padding(12)
            }

            Divider()

            // Defenses
            VStack(alignment: .leading, spacing: 6) {
                Text("DEFENSES")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                ForEach(engine.defenses) { defense in
                    HStack(spacing: 8) {
                        Image(systemName: defense.installed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(defense.installed ? .green : .secondary)
                            .font(.system(size: 12))
                        Text(defense.title)
                            .font(.system(size: 12))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 2)
                }
            }
            .padding(.bottom, 6)

            Divider()

            // Last scan
            VStack(alignment: .leading, spacing: 4) {
                Text("LAST SCAN")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let last = engine.scanHistory.first {
                    HStack {
                        Image(systemName: last.clean ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(last.clean ? .green : .red)
                            .font(.system(size: 12))
                        Text(last.clean ? "Clean" : "\(last.foundIndicators.count) indicator(s) found")
                            .font(.system(size: 12))
                        Spacer()
                        Text(last.date, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No scans yet")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)

            Divider()

            if engine.isAuditing || engine.lastAuditDate != nil {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("GITHUB CREDENTIAL AUDIT")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if engine.isAuditing { ProgressView().controlSize(.mini) }
                        else if let d = engine.lastAuditDate { Text(d, style: .relative).font(.caption2).foregroundStyle(.secondary) }
                    }
                    ForEach(Array(engine.credentialAudit.split(separator: "\n").enumerated()), id: \.offset) { _, line in
                        Text(String(line))
                            .font(.system(size: 11))
                            .foregroundStyle(line.hasPrefix("🚨") ? .red : line.hasPrefix("⚠") ? .orange : .primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)

                Divider()
            }

            // Actions
            VStack(spacing: 6) {
                Button {
                    Task { await engine.runScan() }
                } label: {
                    HStack {
                        if engine.isScanning {
                            ProgressView().controlSize(.small)
                            Text("Scanning…")
                        } else {
                            Image(systemName: "magnifyingglass")
                            Text("Run Scan Now")
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(engine.isScanning)

                Button {
                    Task { await engine.auditCredentials() }
                } label: {
                    HStack {
                        Image(systemName: "key.viewfinder")
                        Text(engine.isAuditing ? "Auditing…" : "Audit GitHub Credentials")
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    HStack {
                        Image(systemName: "rectangle.grid.2x2")
                        Text("Open Dashboard")
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    openWindow(id: "welcome")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        Text("Setup Wizard")
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    NSApp.terminate(nil)
                } label: {
                    HStack {
                        Image(systemName: "power")
                        Text("Quit")
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
        }
        .frame(width: 300)
    }
}
