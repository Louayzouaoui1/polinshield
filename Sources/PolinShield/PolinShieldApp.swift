// PolinShield — Menu bar defense against npm supply-chain malware
// https://github.com/Louay24/polinshield
import SwiftUI
import AppKit
import UserNotifications

// MARK: - App Entry

@main
struct PolinShieldApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var engine = DefenseEngine.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(engine)
        } label: {
            Image(systemName: engine.statusIcon)
                .foregroundStyle(engine.statusColor)
        }
        .menuBarExtraStyle(.window)

        Window("PolinShield Dashboard", id: "dashboard") {
            DashboardView()
                .environmentObject(engine)
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowResizability(.contentSize)

        Window("Welcome to PolinShield", id: "welcome") {
            WelcomeView()
                .environmentObject(engine)
                .frame(width: 580, height: 520)
        }
        .windowResizability(.contentSize)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // Hide dock icon
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        Task { await DefenseEngine.shared.refreshStatus() }
    }
}
