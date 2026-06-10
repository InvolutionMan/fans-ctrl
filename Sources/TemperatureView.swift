import SwiftUI

struct TemperatureView: View {
    let sensors: [TempSensor]

    private var cpuAverage: Double? {
        let cpuSensors = sensors.filter { $0.name == "CPU" || $0.id.hasPrefix("TC") }
        guard !cpuSensors.isEmpty else { return nil }
        return cpuSensors.map(\.celsius).reduce(0, +) / Double(cpuSensors.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CPU 温度")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            if let temp = cpuAverage {
                TempGaugeCard(name: "CPU", celsius: temp)
            } else {
                Text("无可用传感器")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Temp Gauge Card

private struct TempGaugeCard: View {
    let name: String
    let celsius: Double

    private var gaugeColor: Color {
        if celsius < 60 { return .green }
        if celsius < 75 { return .yellow }
        if celsius < 90 { return .orange }
        return .red
    }

    private var statusLabel: String {
        if celsius < 60 { return "正常" }
        if celsius < 75 { return "温热" }
        if celsius < 90 { return "高温" }
        return "过热"
    }

    private var progress: Double {
        min(max(celsius / 110.0, 0), 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(statusLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(gaugeColor.opacity(0.12))
                    .foregroundColor(gaugeColor)
                    .clipShape(Capsule())
            }

            // Gauge bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(gaugeColor)
                        .frame(width: max(0, geo.size.width * progress), height: 6)
                        .animation(.easeOut(duration: 0.4), value: celsius)
                }
            }
            .frame(height: 6)

            // Temperature
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(celsius))")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                Text("°C")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            // Meta
            HStack {
                Text("范围 0–110")
                Spacer()
                Text(statusLabel)
            }
            .font(.system(size: 10))
            .foregroundColor(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
        )
    }
}
