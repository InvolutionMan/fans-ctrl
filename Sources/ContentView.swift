import SwiftUI

struct ContentView: View {
    @EnvironmentObject var monitor: FanMonitor
    @EnvironmentObject var controller: FanController
    @EnvironmentObject var menuBarController: MenuBarController

    var body: some View {
        VStack(spacing: 0) {
            // Titlebar
            TitleBar()

            // Scrollable content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 20) {
                    // Fan gauges + Temperature — side by side
                    HStack(alignment: .top, spacing: 16) {
                        // Left: fan gauges
                        VStack(alignment: .leading, spacing: 12) {
                            Text("风扇概览")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                            ForEach(monitor.fans) { fan in
                                FanGaugeView(fan: fan)
                            }
                        }

                        // Right: temperature
                        TemperatureView(sensors: monitor.temperatures)
                    }

                    // Controls
                    ControlPanelView()

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Status bar
            StatusBar()
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            if geteuid() == 0 {
                controller.updateAvailableSensors(monitor.temperatures)
                controller.syncFromMonitor(fans: monitor.fans)
            }
        }
        .onChange(of: monitor.temperatures) {
            controller.updateAvailableSensors(monitor.temperatures)
        }
        .onReceive(monitor.$fans) { fans in
            // Defer to avoid layout recursion during view update cycle
            DispatchQueue.main.async {
                controller.syncFromMonitor(fans: fans)
            }
        }
        .onDisappear {
            controller.resetAllToAuto()
        }
    }
}

// MARK: - Title Bar

struct TitleBar: View {
    @EnvironmentObject var controller: FanController
    @EnvironmentObject var menuBarController: MenuBarController

    var body: some View {
        HStack(spacing: 10) {
            // Traffic lights
            HStack(spacing: 8) {
                Circle().fill(Color(red: 0.89, green: 0.31, blue: 0.31)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 0.88, green: 0.71, blue: 0.25)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 0.33, green: 0.76, blue: 0.43)).frame(width: 12, height: 12)
            }

            Spacer()

            Text("Mac Fans Control")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary.opacity(0.65))

            Spacer()

            // Menu bar toggles — compact pills
            HStack(spacing: 10) {
                MenuBarToggle(label: "风扇", isOn: $controller.menuBarShowFan) {
                    menuBarController.setShowFan(controller.menuBarShowFan)
                }
                MenuBarToggle(label: "温度", isOn: $controller.menuBarShowTemp) {
                    menuBarController.setShowTemp(controller.menuBarShowTemp)
                }
                MenuBarToggle(label: "图标", isOn: $controller.menuBarIcon) {
                    menuBarController.setVisible(controller.menuBarIcon)
                }
                Divider().frame(height: 12)
                MenuBarToggle(label: "启动", isOn: $controller.startupAuto)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .overlay(Divider(), alignment: .bottom)
    }
}

// MARK: - Status Bar

// MARK: - Menu Bar Toggle (compact)

struct MenuBarToggle: View {
    let label: String
    @Binding var isOn: Bool
    var onChange: (() -> Void)?

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .onChange(of: isOn) { onChange?() }
        }
    }
}

struct StatusBar: View {
    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Circle().fill(Color.green).frame(width: 5, height: 5)
                Text("监控中")
                    .font(.system(size: 10, design: .monospaced))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(Divider(), alignment: .top)
    }
}
