import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var engine: DefenseEngine
    @State private var selectedTab: Tab = .overview

    enum Tab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case defenses = "Defenses"
        case scans = "Scan History"
        case forcePushes = "Force-Pushes"
        case about = "About"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .overview: return "rectangle.grid.2x2"
            case .defenses: return "shield.lefthalf.filled"
            case .scans: return "magnifyingglass"
            case .forcePushes: return "arrow.up.arrow.down"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch selectedTab {
            case .overview: OverviewPane()
            case .defenses: DefensesPane()
            case .scans: ScanHistoryPane()
            case .forcePushes: ForcePushesPane()
            case .about: AboutPane()
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}

// MARK: - Overview

struct OverviewPane: View {
    @EnvironmentObject var engine: DefenseEngine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Hero status
                HStack(spacing: 16) {
                    Image(systemName: engine.statusIcon)
                        .foregroundStyle(engine.statusColor)
                        .font(.system(size: 56))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(engine.statusText)
                            .font(.system(size: 28, weight: .semibold))
                        if let last = engine.lastScanDate {
                            Text("Last scan \(last, style: .relative) ago")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No scans yet")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        Task { await engine.runScan() }
                    } label: {
                        if engine.isScanning {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Scan Now", systemImage: "magnifyingglass")
                        }
                    }
                    .controlSize(.large)
                    .disabled(engine.isScanning)
                }

                // Stats grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    StatCard(label: "Defenses Active",
                             value: "\(engine.defenses.filter { $0.installed }.count)/\(engine.defenses.count)",
                             icon: "shield.lefthalf.filled",
                             color: .blue)
                    StatCard(label: "Total Scans",
                             value: "\(engine.scanHistory.count)",
                             icon: "magnifyingglass",
                             color: .green)
                    StatCard(label: "Threats Found",
                             value: "\(engine.scanHistory.flatMap { $0.foundIndicators }.count)",
                             icon: "exclamationmark.triangle",
                             color: .red)
                }

                // Defense summary
                GroupBox("Defense Layers") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(engine.defenses) { d in
                            HStack {
                                Image(systemName: d.installed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(d.installed ? .green : .secondary)
                                Text(d.title)
                                Spacer()
                                Text(d.installed ? "Active" : "Inactive")
                                    .foregroundStyle(d.installed ? .green : .secondary)
                                    .font(.caption)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(8)
                }
            }
            .padding(24)
        }
        .navigationTitle("Overview")
    }
}

struct StatCard: View {
    let label: String
    let value: String
    let icon: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).foregroundStyle(color)
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            Text(value).font(.system(size: 32, weight: .semibold, design: .rounded))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Defenses

struct DefensesPane: View {
    @EnvironmentObject var engine: DefenseEngine
    @State private var sudoPassword = ""
    @State private var showingSudoPrompt = false
    @State private var pendingDefense: Defense.ID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !engine.lastInstallOutput.isEmpty {
                    GroupBox("Last Install Output") {
                        ScrollView {
                            Text(engine.lastInstallOutput)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(height: 100)
                    }
                }

                ForEach(engine.defenses) { defense in
                    GroupBox {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: defense.installed ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(defense.installed ? .green : .secondary)
                                .font(.system(size: 22))
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(defense.title).font(.headline)
                                Text(defense.description)
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                                if defense.needsSudo {
                                    Label("Requires admin password", systemImage: "lock")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            if defense.installed {
                                Text("ACTIVE")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(.green.opacity(0.15))
                                    .clipShape(Capsule())
                            } else {
                                Button("Install") {
                                    if defense.needsSudo {
                                        pendingDefense = defense.id
                                        showingSudoPrompt = true
                                    } else {
                                        Task { await engine.installDefense(defense.id) }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Defenses")
        .sheet(isPresented: $showingSudoPrompt) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Administrator Required")
                    .font(.headline)
                Text("This defense modifies /etc/hosts and needs your admin password.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SecureField("Password", text: $sudoPassword)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { showingSudoPrompt = false; sudoPassword = "" }
                    Button("Install") {
                        if let id = pendingDefense {
                            Task {
                                await engine.installDefense(id, sudoPassword: sudoPassword)
                                sudoPassword = ""
                            }
                        }
                        showingSudoPrompt = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 380)
        }
    }
}

// MARK: - Scan History

struct ScanHistoryPane: View {
    @EnvironmentObject var engine: DefenseEngine
    @State private var selected: ScanResult.ID?

    var body: some View {
        VSplitView {
            if engine.scanHistory.isEmpty {
                ContentUnavailableView("No scans yet", systemImage: "magnifyingglass",
                                       description: Text("Run your first scan from the menu bar or Overview tab."))
            } else {
                Table(engine.scanHistory, selection: $selected) {
                    TableColumn("Status") { scan in
                        Image(systemName: scan.clean ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(scan.clean ? .green : .red)
                    }.width(50)
                    TableColumn("Date") { scan in
                        Text(scan.date.formatted(date: .abbreviated, time: .standard))
                    }
                    TableColumn("Result") { scan in
                        Text(scan.clean ? "Clean" : "\(scan.foundIndicators.count) indicator(s)")
                    }
                    TableColumn("Exit Code") { scan in
                        Text("\(scan.exitCode)")
                    }.width(80)
                }
                .frame(minHeight: 200)

                if let id = selected, let scan = engine.scanHistory.first(where: { $0.id == id }) {
                    GroupBox("Scan Output") {
                        ScrollView {
                            Text(scan.log.isEmpty ? "(empty)" : scan.log)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(8)
                        }
                    }
                    .padding(8)
                    .frame(minHeight: 150)
                }
            }
        }
        .navigationTitle("Scan History")
    }
}

// MARK: - Force Pushes

struct ForcePushesPane: View {
    @EnvironmentObject var engine: DefenseEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toolbar
            HStack {
                if let last = engine.lastForcePushCheck {
                    Text("Last check: \(last, style: .relative) ago")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    Text("Not yet checked").foregroundStyle(.secondary).font(.caption)
                }
                Spacer()
                Button {
                    Task { await engine.checkForcePushes(notify: false) }
                } label: {
                    if engine.isCheckingForcePushes {
                        HStack { ProgressView().controlSize(.small); Text("Checking…") }
                    } else {
                        Label("Check Now", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(engine.isCheckingForcePushes)
            }
            .padding()

            Divider()

            if engine.forcePushHistory.isEmpty {
                ContentUnavailableView {
                    Label("No force-pushes detected", systemImage: "checkmark.shield")
                } description: {
                    Text("Click 'Check Now' or wait for the hourly auto-check.\nRequires gh CLI authenticated: gh auth login")
                }
            } else {
                List(engine.forcePushHistory) { event in
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(event.repo).font(.system(.body, weight: .semibold))
                                Text("/").foregroundStyle(.secondary)
                                Text(event.branch).font(.system(.body, design: .monospaced))
                            }
                            HStack(spacing: 4) {
                                Text(event.beforeSha).font(.caption.monospaced()).foregroundStyle(.secondary)
                                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                                Text(event.headSha).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(event.date, style: .relative).font(.caption).foregroundStyle(.secondary)
                            Link("View on GitHub →", destination: URL(string: "https://github.com/\(event.repo)/commit/\(event.headSha)")!)
                                .font(.caption2)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Force-Pushes")
    }
}

// MARK: - About

struct AboutPane: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "shield.lefthalf.filled.checkmark")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("PolinShield").font(.largeTitle.weight(.semibold))
            Text("Version 1.0.0").foregroundStyle(.secondary)
            Text("Defense against npm supply-chain malware\non macOS development machines.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com/Louay24/polinshield")!)
                Link("Report Issue", destination: URL(string: "https://github.com/Louay24/polinshield/issues")!)
                Link("Documentation", destination: URL(string: "https://github.com/Louay24/polinshield/blob/main/README.md")!)
            }
            Spacer()
            Text("MIT License · Built after the 2026 PolinRider/openclaw incident")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("About")
    }
}
