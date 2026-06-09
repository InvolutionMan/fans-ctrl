import SwiftUI

struct ContentView: View {
    @EnvironmentObject var monitor: FanMonitor
    @EnvironmentObject var controller: FanController

    var body: some View {
        VStack(spacing: 0) {
            // Titlebar
            TitleBar()

            // Scrollable content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 14) {
                    // Header
                    HStack {
                        Text("风扇概览")
                            .font(.system(size: 18, weight: .bold))
                        Spacer()
                    }
                    .padding(.bottom, 4)

                    // Fan gauges
                    HStack(spacing: 14) {
                        ForEach(monitor.fans) { fan in
                            FanGaugeView(fan: fan)
                        }
                    }

                    // Temperature
                    TemperatureView(averageCPUTemperature: monitor.averageCPUTemperature)

                    // Controls
                    ControlPanelView()

                    Spacer(minLength: 16)
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Status bar
            StatusBar()
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Title Bar

struct TitleBar: View {
    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                Circle().fill(Color(red: 0.89, green: 0.31, blue: 0.31)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 0.88, green: 0.71, blue: 0.25)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 0.33, green: 0.76, blue: 0.43)).frame(width: 12, height: 12)
                Spacer()
            }
            .padding(.leading, 14)

            Text("Mac Fans Control")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary.opacity(0.7))
        }
        .frame(height: 44)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.85))
        .overlay(Divider(), alignment: .bottom)
    }
}

// MARK: - Status Bar

struct StatusBar: View {
    @State private var time = ""

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Circle().fill(Color.green).frame(width: 5, height: 5)
                Text("监控中")
                    .font(.system(size: 10, design: .monospaced))
            }
            Spacer()
            Text(time)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(Divider(), alignment: .top)
        .onAppear { updateTime() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            updateTime()
        }
    }

    private func updateTime() {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        time = f.string(from: Date())
    }
}
