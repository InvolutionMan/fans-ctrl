import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if geteuid() != 0 {
            escalateAndRestart()
            return
        }

        // root 实例：激活窗口
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where !window.className.contains("StatusBar") {
                window.delegate = self
                window.isReleasedWhenClosed = false
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    /// 通过终端 sudo 提权，保留用户 UI 会话（可访问菜单栏）
    private func escalateAndRestart() {
        guard let exec = Bundle.main.executablePath else { return }

        let source = """
        tell application "Terminal"
            activate
            do script "sudo \\"\(exec)\\""
        end tell
        """

        if let appleScript = NSAppleScript(source: source) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            exit(0)
        }
    }
}

@main
struct FansCtrlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor: FanMonitor
    @StateObject private var controller = FanController()
    @StateObject private var menuBarController: MenuBarController

    init() {
        let monitor = FanMonitor()
        _monitor = StateObject(wrappedValue: monitor)
        _menuBarController = StateObject(wrappedValue: MenuBarController(monitor: monitor))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(monitor)
                .environmentObject(controller)
                .environmentObject(menuBarController)
                .frame(minWidth: 680, minHeight: 520)
                .onAppear { monitor.startPolling() }
                .onDisappear { monitor.stopPolling() }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 720, height: 560)
    }
}
