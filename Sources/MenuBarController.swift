import SwiftUI
import AppKit
import Combine

class MenuBarController: ObservableObject {
    private var statusItem: NSStatusItem?
    private var cancellable: AnyCancellable?
    private var monitor: FanMonitor
    private var fanIconView: AnimatedFanIconView?
    private var showFan: Bool = true
    private var showTemp: Bool = true

    init(monitor: FanMonitor) {
        self.monitor = monitor
        if geteuid() == 0 {
            DispatchQueue.main.async {
                self.setVisible(true)
            }
        }
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

    private func updateDisplay(temp: Double?) {
        // 风扇图标显隐
        fanIconView?.isHidden = !showFan

        if let temp = temp, temp > 0 {
            if showTemp {
                let prefix = showFan ? "    " : "  "
                statusItem?.button?.title = String(format: "%@%.1f°C", prefix, temp)
            } else {
                statusItem?.button?.title = showFan ? "  " : ""
            }
            if showFan {
                fanIconView?.setActiveAppearance()
                fanIconView?.updateSpeed(temperature: temp)
            }
        } else {
            if showTemp {
                let prefix = showFan ? "    " : "  "
                statusItem?.button?.title = "\(prefix)--°C"
            } else {
                statusItem?.button?.title = showFan ? "  " : ""
            }
            if showFan {
                fanIconView?.setIdleAppearance()
                fanIconView?.stopSpin()
            }
        }
    }

    // MARK: - Individual Element Control

    func setShowFan(_ show: Bool) {
        showFan = show
        updateDisplay(temp: monitor.averageCPUTemperature)
    }

    func setShowTemp(_ show: Bool) {
        showTemp = show
        updateDisplay(temp: monitor.averageCPUTemperature)
    }

    // MARK: - Menu Bar Setup

    func setVisible(_ visible: Bool) {
        if visible {
            if statusItem == nil {
                setupStatusItem()
                cancellable?.cancel()
                observeTemperature()
            }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            // 用自定义旋转风扇视图替换静态 SF Symbol
            let iconSize: CGFloat = 18
            let fanView = AnimatedFanIconView(size: iconSize)
            fanView.setIdleAppearance()
            button.addSubview(fanView)

            // 垂直居中，左侧留出间距
            fanView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                fanView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 4),
                fanView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                fanView.widthAnchor.constraint(equalToConstant: iconSize),
                fanView.heightAnchor.constraint(equalToConstant: iconSize),
            ])

            fanIconView = fanView

            button.title = "    --°C"
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
            window.level = .floating
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
