import SwiftUI

struct ControlPanelView: View {
    @EnvironmentObject var controller: FanController
    @EnvironmentObject var monitor: FanMonitor

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("风扇控制")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if let error = controller.lastError {
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.red.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                // Mode selector
                HStack(spacing: 2) {
                    ForEach(FanMode.allCases) { mode in
                        Button(action: {
                            controller.setMode(mode)
                        }) {
                            Text(mode.rawValue)
                                .font(.system(size: 11, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .padding(.horizontal, 10)
                                .background(controller.mode == mode ? Color.gray.opacity(0.25) : Color.clear)
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

                // Manual mode — per-fan controls
                if controller.mode == .manual {
                    VStack(spacing: 10) {
                        ForEach(monitor.fans) { fan in
                            PerFanControlView(fan: fan)
                        }
                    }
                    .transition(.opacity)
                }

                // Sensor mode
                if controller.mode == .sensor {
                    VStack(spacing: 10) {
                        VStack(spacing: 10) {
                            SliderRow(label: "最低转速", value: $controller.sliderMin, range: 1800...5800, unit: "RPM")
                            SliderRow(label: "最高转速", value: $controller.sliderMax, range: 2000...6200, unit: "RPM")
                        }

                        Divider()

                        Text("温度联动设置")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack {
                            Text("监控传感器")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: $controller.selectedSensorID) {
                                ForEach(controller.availableSensors) { sensor in
                                    Text(sensor.name).tag(sensor.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 150)
                        }

                        VStack(spacing: 4) {
                            HStack {
                                Text("目标温度")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(Int(controller.targetTemperature))°C")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .monospacedDigit()
                                    .foregroundColor(.primary)
                            }
                            Slider(value: $controller.targetTemperature, in: 50...95, step: 1)
                                .controlSize(.small)
                        }

                        VStack(spacing: 4) {
                            HStack {
                                Text("温滞范围")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("±\(Int(controller.tempHysteresis))°C")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .monospacedDigit()
                                    .foregroundColor(.primary)
                            }
                            Slider(value: $controller.tempHysteresis, in: 1...10, step: 1)
                                .controlSize(.small)
                        }

                        if let currentTemp = controller.availableSensors.first(where: { $0.id == controller.selectedSensorID })?.celsius {
                            HStack {
                                Text("当前温度")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(Int(currentTemp))°C")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(currentTemp > controller.targetTemperature ? .orange : .green)

                                Text("→")
                                    .foregroundColor(.secondary)

                                Text("\(controller.calculateFanSpeed(currentTemperature: currentTemp)) RPM")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .transition(.opacity)
                }

            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 0.5))

            VStack(alignment: .leading, spacing: 10) {
                Text("预设方案")
                    .font(.system(size: 13, weight: .semibold))

                VStack(spacing: 5) {
                    PresetButton(title: "均衡", desc: "自动调节，日常使用", preset: .balanced)
                    PresetButton(title: "安静", desc: "低转速，降噪优先", preset: .quiet)
                    PresetButton(title: "性能", desc: "高转速，散热优先", preset: .performance)
                    PresetButton(title: "全速", desc: "最大转速，极限散热", preset: .fullSpeed)
                }
            }
            .padding(14)
            .frame(width: 200)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.15), lineWidth: 0.5))
        }
    }
}

// MARK: - Per-Fan Control

struct PerFanControlView: View {
    let fan: Fan
    @EnvironmentObject var controller: FanController
    @State private var localRPM: Double = 3000
    @State private var isSyncing = false

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(fan.name)
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(Int(localRPM)) RPM")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(.accentColor)
            }

            Slider(value: $localRPM, in: Double(fan.minRPM)...Double(fan.maxRPM), step: 50)
                .controlSize(.small)
                .onChange(of: localRPM) {
                    guard !isSyncing else { return }
                    controller.setFanRPM(localRPM, fanIndex: fan.id)
                }
        }
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear {
            syncFromController()
        }
        .onChange(of: controller.fanTargetRPMs[fan.id]) {
            syncFromController()
        }
    }

    private func syncFromController() {
        let target = controller.fanTargetRPMs[fan.id] ?? Double(fan.targetRPM > 0 ? fan.targetRPM : 3000)
        let clamped = max(Double(fan.minRPM), min(Double(fan.maxRPM), target))
        guard localRPM != clamped else { return }
        isSyncing = true
        localRPM = clamped
        isSyncing = false
    }
}

// MARK: - Shared Components

struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label).font(.system(size: 11)).foregroundColor(.secondary)
                Spacer()
                Text("\(Int(value)) \(unit)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(.primary)
            }
            Slider(value: $value, in: range, step: 100)
                .controlSize(.small)
        }
    }
}

struct ToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(label).font(.system(size: 12))
            Spacer()
            Toggle("", isOn: $isOn).toggleStyle(.switch).controlSize(.small)
        }
        .padding(.vertical, 8)
        .overlay(Divider(), alignment: .bottom)
    }
}

struct PresetButton: View {
    let title: String
    let desc: String
    let preset: Preset
    @EnvironmentObject var controller: FanController

    var isActive: Bool { controller.activePreset == preset }

    var body: some View {
        Button(action: { controller.applyPreset(preset) }) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 11, weight: .semibold))
                Text(desc).font(.system(size: 9)).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isActive ? Color.accentColor.opacity(0.1) : Color(NSColor.windowBackgroundColor))
            .foregroundColor(isActive ? .accentColor : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(isActive ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
