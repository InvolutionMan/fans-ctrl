import Foundation
import IOKit

// MARK: - Enums

enum FanMode: String, CaseIterable, Identifiable {
    case auto = "自动"
    case manual = "手动"
    var id: String { rawValue }
}

enum Preset: String, CaseIterable, Identifiable {
    case balanced   = "均衡"
    case quiet      = "安静"
    case medium     = "中速"
    case performance = "性能"
    case fullSpeed  = "全速"
    var id: String { rawValue }
}

// MARK: - Fan Controller

class FanController: ObservableObject {
    @Published var mode: FanMode = .auto
    @Published var activePreset: Preset = .balanced
    @Published var targetRPM: Double = 3500
    @Published var menuBarIcon = true
    @Published var canWrite = false
    @Published var statusMessage = ""

    let minAllowedRPM: Double = 1000
    let maxAllowedRPM: Double = 6500

    private var privObserver: NSObjectProtocol?

    init() {
        privObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("PrivilegesGranted"),
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.canWrite = true
            self?.applyFanSettings()
        }
    }

    // MARK: - Presets

    func applyPreset(_ preset: Preset) {
        activePreset = preset
        switch preset {
        case .balanced:   mode = .auto
        case .quiet:      mode = .manual; targetRPM = 2000
        case .medium:     mode = .manual; targetRPM = 3500
        case .performance: mode = .manual; targetRPM = 4500
        case .fullSpeed:  mode = .manual; targetRPM = 6000
        }
        applyFanSettings()
    }

    // MARK: - Fan Control

    func applyFanSettings() {
        guard let conn = SMCConnection() else {
            statusMessage = "SMC 不可用"
            return
        }
        defer { conn.close() }

        let fanCount = Int(conn.readFloat("FNum") ?? 1)

        // Test if we can write
        if !canWrite && mode == .manual {
            if conn.writeByte("F0Md", 1) {
                canWrite = true
                statusMessage = "风扇控制已启用"
            } else {
                statusMessage = "需要管理员权限才能控制风扇"
                return
            }
        }

        guard canWrite || mode == .auto else { return }

        for i in 0..<max(1, fanCount) {
            if mode == .auto {
                conn.writeByte("F\(i)Md", 0)
            } else {
                conn.writeByte("F\(i)Md", 1)
                // fpe2 编码: RPM << 2
                conn.writeUInt16("F\(i)Tg", UInt16(Int(targetRPM)) << 2)
            }
        }
    }

    func resetToAuto() {
        mode = .auto
        applyFanSettings()
    }
}
