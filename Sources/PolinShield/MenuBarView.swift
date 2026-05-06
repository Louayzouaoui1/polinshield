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
