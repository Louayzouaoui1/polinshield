import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var engine: DefenseEngine
    @State private var step = 0
    @State private var sudoPassword = ""
    @State private var checkResults: [String] = []
    @State private var isChecking = false
    @State private var isInstalling = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "shield.lefthalf.filled.checkmark")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text("Welcome to PolinShield")
                    .font(.largeTitle.weight(.semibold))
                Text("5-layer defense against npm supply-chain malware")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)
            .padding(.bottom, 30)

            // Step content
            Group {
                switch step {
                case 0: introStep
                case 1: checkStep
                case 2: installStep
                default: doneStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Footer buttons
            HStack {
                if step > 0 && step < 3 {
                    Button("Back") { step -= 1 }
                }
                Spacer()
                Button(step == 3 ? "Done" : "Continue") {
                    if step < 3 { step += 1 } else {
                        UserDefaults.standard.set(true, forKey: "didCompleteWelcome")
                        NSApp.keyWindow?.close()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .disabled(isChecking || isInstalling)
            }
            .padding(20)
        }
    }

    // MARK: Steps

    var introStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This will:")
                .font(.headline)
            FeatureBullet(icon: "magnifyingglass", text: "Scan your Mac for known malware indicators")
            FeatureBullet(icon: "shield.lefthalf.filled", text: "Install 5 defense layers (npm, hosts, git hook, watchers, scans)")
            FeatureBullet(icon: "bell", text: "Send macOS notifications for any detection")
            FeatureBullet(icon: "menubar.dock.rectangle", text: "Live status in your menu bar")
            Text("Layer 2 (DNS-block C2 servers) needs your admin password. Everything else is harmless.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .padding(.horizontal, 40)
    }

    var checkStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step 1: Check for existing infection")
                .font(.headline)
            Text("Read-only — no changes will be made.")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(checkResults, id: \.self) { line in
                        Text(line).font(.system(.caption, design: .monospaced))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .frame(height: 200)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Button {
                    Task { await runCheck() }
                } label: {
                    if isChecking {
                        HStack { ProgressView().controlSize(.small); Text("Checking…") }
                    } else {
                        Label("Run Check", systemImage: "magnifyingglass")
                    }
                }
                .controlSize(.large)
                .disabled(isChecking)
                Spacer()
            }
        }
        .padding(.horizontal, 40)
    }

    var installStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step 2: Install defenses")
                .font(.headline)
            Text("Enter your admin password (used only for /etc/hosts modification).")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            SecureField("Admin password", text: $sudoPassword)
                .textFieldStyle(.roundedBorder)
            Button {
                Task { await runInstall() }
            } label: {
                if isInstalling {
                    HStack { ProgressView().controlSize(.small); Text("Installing…") }
                } else {
                    Label("Install All Defenses", systemImage: "arrow.down.circle")
                }
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(isInstalling || sudoPassword.isEmpty)
        }
        .padding(.horizontal, 40)
    }

    var doneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("All set!")
                .font(.title.weight(.semibold))
            VStack(alignment: .leading, spacing: 6) {
                Text("Things still to do manually:").font(.subheadline.weight(.semibold))
                Text("• Rotate your GitHub PAT at github.com/settings/tokens").font(.subheadline)
                Text("• Rotate npm/GitLab tokens in ~/.npmrc").font(.subheadline)
                Text("• Reboot your Mac").font(.subheadline)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 40)
        }
    }

    // MARK: Actions

    func runCheck() async {
        isChecking = true
        defer { isChecking = false }
        checkResults = ["→ Starting infection check..."]
        await engine.refreshStatus()
        await engine.runScan()
        if let last = engine.scanHistory.first {
            checkResults = [last.clean ? "✅ No infection found" : "🚨 Found \(last.foundIndicators.count) indicator(s)"]
            checkResults += last.foundIndicators
        }
    }

    func runInstall() async {
        isInstalling = true
        defer { isInstalling = false }
        await engine.installAllDefenses(sudoPassword: sudoPassword)
        sudoPassword = ""
        step = 3
    }
}

struct FeatureBullet: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 24)
            Text(text)
            Spacer()
        }
    }
}
