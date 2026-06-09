import SwiftUI
import AppKit

// MARK: - Privileged SMC helper

private func requestAdminAndWrite() {
    let bin = "/Users/yonderdiary/Desktop/fans ctrl/.build/debug/FansCtrl"
    let scriptStr = "do shell script \"'\(bin)' smc-write F0Md 1\" with administrator privileges"

    guard let s = NSAppleScript(source: scriptStr) else { return }
    var err: NSDictionary?
    s.executeAndReturnError(&err)
    if let e = err {
        print("提权失败: \(e)")
    } else {
        print("提权成功")
        // Refresh controller state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Notification to retry
            NotificationCenter.default.post(name: NSNotification.Name("PrivilegesGranted"), object: nil)
        }
    }
}

// MARK: - View

struct ControlPanelView: View {
    @EnvironmentObject var controller: FanController

    var body: some View {
        HStack(spacing: 14) {
            // 左侧：模式 + 滑块
            VStack(alignment: .leading, spacing: 12) {
                Text("风扇控制")
                    .font(.system(size: 13, weight: .semibold))

                // 自动 / 手动 切换
                HStack(spacing: 2) {
                    ForEach(FanMode.allCases) { mode in
                        Button {
                            controller.mode = mode
                            controller.applyFanSettings()
                        } label: {
                            Text(mode.rawValue)
                                .font(.system(size: 11, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(controller.mode == mode
                                    ? Color.gray.opacity(0.3) : Color.clear)
                                .foregroundColor(controller.mode == mode ? .primary : .secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    }
                }
                .padding(2)
                .background(Color(NSColor.windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // 手动模式下显示目标转速滑块
                if controller.mode == .manual {
                    VStack(spacing: 4) {
                        HStack {
                            Text("目标转速")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(controller.targetRPM)) RPM")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .monospacedDigit()
                                .foregroundColor(.primary)
                        }
                        Slider(value: $controller.targetRPM,
                               in: 1000...6500, step: 100)
                            .controlSize(.small)
                            .onChange(of: controller.targetRPM) { _, _ in
                                controller.applyFanSettings()
                            }
                    }
                    .transition(.opacity)
                }

                // Status
                if !controller.statusMessage.isEmpty {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(controller.canWrite ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text(controller.statusMessage)
                            .font(.system(size: 10))
                            .foregroundColor(controller.canWrite ? .green : .orange)
                        Spacer()
                        if !controller.canWrite {
                            Button("解锁风扇控制") {
                                requestAdminAndWrite()
                            }
                            .font(.system(size: 10))
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Toggles
                VStack(spacing: 0) {
                    ToggleRow(label: "菜单栏图标", isOn: $controller.menuBarIcon)
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
            )

            // 右侧：预设方案
            VStack(alignment: .leading, spacing: 12) {
                Text("预设方案")
                    .font(.system(size: 13, weight: .semibold))

                VStack(spacing: 6) {
                    PresetButton(title: "均衡",   desc: "自动调节，日常使用",       preset: .balanced)
                    PresetButton(title: "安静",   desc: "2000 RPM，降噪优先",       preset: .quiet)
                    PresetButton(title: "中速",   desc: "3500 RPM，均衡散热",       preset: .medium)
                    PresetButton(title: "性能",   desc: "4500 RPM，散热优先",       preset: .performance)
                    PresetButton(title: "全速",   desc: "6000 RPM，极限散热",       preset: .fullSpeed)
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Toggle Row

struct ToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 8)
        .overlay(Divider(), alignment: .bottom)
    }
}

// MARK: - Preset Button

struct PresetButton: View {
    let title: String
    let desc: String
    let preset: Preset
    @EnvironmentObject var controller: FanController

    var isActive: Bool { controller.activePreset == preset }

    var body: some View {
        Button { controller.applyPreset(preset) } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text(desc)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(isActive
                ? Color.accentColor.opacity(0.12)
                : Color(NSColor.windowBackgroundColor))
            .foregroundColor(isActive ? .accentColor : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? Color.accentColor.opacity(0.4) : Color.gray.opacity(0.15),
                            lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
