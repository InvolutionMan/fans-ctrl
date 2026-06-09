import SwiftUI
import AppKit
import Combine

class MenuBarController: ObservableObject {
    private var statusItem: NSStatusItem?
    private var cancellable: AnyCancellable?
    private var monitor: FanMonitor

    init(monitor: FanMonitor) {
        self.monitor = monitor
        setupStatusItem()
        observeTemperature()
    }

    deinit {
        cancellable?.cancel()
    }

    // MARK: - Observe FanMonitor

    private func observeTemperature() {
        cancellable = monitor.$averageCPUTemperature
            .receive(on: DispatchQueue.main)
            .sink { [weak self] temp in
                self?.updateDisplay(temp: temp)
            }
        updateDisplay(temp: monitor.averageCPUTemperature)
    }

    private func updateDisplay(temp: Double) {
        if temp > 0 {
            statusItem?.button?.title = String(format: "%.1f°C", temp)
        } else {
            statusItem?.button?.title = "--°C"
        }
    }

    // MARK: - Menu Bar Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.title = "--°C"
            button.action = #selector(statusBarButtonClicked)
            button.target = self
        }

        setupMenu()
    }

    private func setupMenu() {
        let menu = NSMenu()

        let showWindowItem = NSMenuItem(title: "显示主窗口", action: #selector(showMainWindow), keyEquivalent: "")
        showWindowItem.target = self
        menu.addItem(showWindowItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func statusBarButtonClicked() {
        showMainWindow()
    }

    @objc private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.unhide(nil)

        for window in NSApp.windows where !window.className.contains("StatusBar") {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
