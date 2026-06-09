import SwiftUI
import AppKit

// MARK: - CLI Mode

private func handleCLI() -> Bool {
    let args = CommandLine.arguments
    guard args.count >= 4, args[1] == "smc-write" else { return false }

    let key = args[2]
    let val = UInt8(args[3]) ?? 0

    guard let conn = SMCConnection() else {
        print("SMC unavailable"); exit(1)
    }

    let ok = conn.writeByte(key, val)
    print(ok ? "OK" : "ERR")
    exit(ok ? 0 : 1)
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            for window in NSApp.windows where !window.className.contains("StatusBar") {
                window.delegate = self
                window.isReleasedWhenClosed = false
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

// MARK: - App

@main
struct FansCtrlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor: FanMonitor
    @StateObject private var controller = FanController()
    @StateObject private var menuBarController: MenuBarController

    init() {
        _ = handleCLI()  // exits process if CLI mode

        let monitor = FanMonitor()
        _monitor = StateObject(wrappedValue: monitor)
        _menuBarController = StateObject(wrappedValue: MenuBarController(monitor: monitor))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(monitor)
                .environmentObject(controller)
                .frame(minWidth: 680, minHeight: 520)
                .onAppear {
                    monitor.startPolling(interval: 1.0)
                }
                .onDisappear {
                    monitor.stopPolling()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 720, height: 560)
    }
}
